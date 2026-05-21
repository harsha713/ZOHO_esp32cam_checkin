#!/bin/bash
# =============================================================================
# ZOHO SMART KIOSK — ESP32-CAM to Virtual Camera Bridge
# Pulls MJPEG stream from ESP32-CAM and feeds into /dev/video10
# so Chromium sees it as a real webcam.
# =============================================================================

# ─── USER CONFIG — EDIT THIS ─────────────────────────────────────────────────
ESP32_CAM_IP="192.168.1.100"   # ← Replace with your ESP32-CAM's IP address
ESP32_CAM_PORT="80"
ESP32_STREAM_PATH="/stream"
VIRTUAL_CAM_DEVICE="/dev/video10"
# ─────────────────────────────────────────────────────────────────────────────

STREAM_URL="http://${ESP32_CAM_IP}:${ESP32_CAM_PORT}${ESP32_STREAM_PATH}"
LOGDIR="/var/log/zoho-kiosk"
mkdir -p "$LOGDIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGDIR/camera-feed.log"; }

log "=== ESP32-CAM Camera Feed Bridge starting ==="
log "Source: $STREAM_URL"
log "Target: $VIRTUAL_CAM_DEVICE"

# ── Ensure v4l2loopback device exists ────────────────────────────────────────
if [ ! -e "$VIRTUAL_CAM_DEVICE" ]; then
    log "Virtual camera device not found. Loading v4l2loopback..."
    sudo modprobe v4l2loopback \
        devices=1 \
        video_nr=10 \
        card_label="ZohoKioskCam" \
        exclusive_caps=1
    sleep 2
fi

if [ ! -e "$VIRTUAL_CAM_DEVICE" ]; then
    log "ERROR: Could not create $VIRTUAL_CAM_DEVICE. Exiting."
    exit 1
fi

log "Virtual camera device ready: $VIRTUAL_CAM_DEVICE"

# ── Main loop: connect to ESP32-CAM and bridge to virtual cam ────────────────
RETRY_DELAY=5
CONSECUTIVE_FAILURES=0

while true; do
    log "Connecting to ESP32-CAM at $STREAM_URL ..."

    # Wait for ESP32-CAM to be reachable
    while ! curl -s --max-time 3 "http://${ESP32_CAM_IP}/" > /dev/null 2>&1; do
        log "ESP32-CAM not reachable. Waiting ${RETRY_DELAY}s..."
        sleep "$RETRY_DELAY"
    done

    log "ESP32-CAM online. Starting ffmpeg bridge..."

    # ffmpeg reads the MJPEG stream and writes to the v4l2loopback device
    # -re              : read at native frame rate
    # -f mjpeg         : input format is MJPEG
    # -i <url>         : input is the ESP32-CAM stream URL
    # -vf scale=640:480: scale to standard VGA (Zoho works well with this)
    # -f v4l2          : output as a V4L2 video device
    ffmpeg \
        -loglevel warning \
        -f mjpeg \
        -framerate 15 \
        -i "$STREAM_URL" \
        -vf scale=640:480,format=yuv420p \
        -f v4l2 \
        "$VIRTUAL_CAM_DEVICE" \
        >> "$LOGDIR/ffmpeg.log" 2>&1

    EXIT_CODE=$?
    CONSECUTIVE_FAILURES=$((CONSECUTIVE_FAILURES + 1))

    if [ $CONSECUTIVE_FAILURES -ge 5 ]; then
        log "WARNING: $CONSECUTIVE_FAILURES consecutive failures. Something may be wrong."
        RETRY_DELAY=30   # Back off to avoid log spam
    fi

    log "ffmpeg exited (code $EXIT_CODE). Reconnecting in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
done
