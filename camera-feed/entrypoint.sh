#!/bin/bash
# =============================================================================
# ZOHO KIOSK — Camera Feed Container Entrypoint
# Pulls MJPEG stream from ESP32-CAM → writes to /dev/video10 (v4l2loopback)
# =============================================================================

set -e

ESP32_CAM_IP="${ESP32_CAM_IP:-192.168.1.101}"
ESP32_CAM_PORT="${ESP32_CAM_PORT:-80}"
ESP32_CAM_STREAM_PATH="${ESP32_CAM_STREAM_PATH:-/stream}"
VIRTUAL_DEVICE="/dev/video10"

STREAM_URL="http://${ESP32_CAM_IP}:${ESP32_CAM_PORT}${ESP32_CAM_STREAM_PATH}"
RETRY_DELAY=5

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CAMERA] $1"; }

log "=== ESP32-CAM Camera Feed Bridge ==="
log "  Source: $STREAM_URL"
log "  Target: $VIRTUAL_DEVICE"

# ── Verify virtual camera device exists ───────────────────────────────────────
if [ ! -e "$VIRTUAL_DEVICE" ]; then
    log "ERROR: $VIRTUAL_DEVICE not found on host!"
    log "Did you run host-setup.sh on the server first? It loads the v4l2loopback kernel module."
    log "Command: bash host-setup.sh"
    log "Waiting 30s before exit so you can read this in Portainer logs..."
    sleep 30
    exit 1
fi
log "Virtual camera device exists: $VIRTUAL_DEVICE ✓"

# ── Wait for ESP32-CAM to come online, then bridge ────────────────────────────
CONSECUTIVE_FAILS=0

while true; do
    log "Waiting for ESP32-CAM at ${ESP32_CAM_IP}..."

    # Poll until ESP32-CAM is reachable
    until curl -s --max-time 3 "http://${ESP32_CAM_IP}/" > /dev/null 2>&1; do
        sleep "$RETRY_DELAY"
    done

    log "ESP32-CAM online! Starting ffmpeg bridge..."
    CONSECUTIVE_FAILS=0

    # ffmpeg: read MJPEG stream → convert → write to v4l2 device
    ffmpeg \
        -loglevel warning \
        -f mjpeg \
        -framerate 15 \
        -i "$STREAM_URL" \
        -vf "scale=640:480,format=yuv420p" \
        -f v4l2 \
        "$VIRTUAL_DEVICE"

    EXIT_CODE=$?
    CONSECUTIVE_FAILS=$((CONSECUTIVE_FAILS + 1))

    if [ $CONSECUTIVE_FAILS -ge 5 ]; then
        log "WARNING: $CONSECUTIVE_FAILS consecutive failures. Backing off to 30s..."
        RETRY_DELAY=30
    fi

    log "ffmpeg exited (code $EXIT_CODE). Reconnecting in ${RETRY_DELAY}s..."
    sleep "$RETRY_DELAY"
done
