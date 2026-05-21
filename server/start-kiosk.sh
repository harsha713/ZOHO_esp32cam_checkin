#!/bin/bash
# =============================================================================
# ZOHO SMART KIOSK — Chromium Kiosk Launcher
# This script starts a virtual display and opens Zoho Kiosk in full-screen
# Chromium. Edit the ZOHO_KIOSK_URL below before running.
# =============================================================================

# ─── USER CONFIG — EDIT THESE ────────────────────────────────────────────────
ZOHO_KIOSK_URL="https://people.zoho.in/YourCompany/kiosk"
DISPLAY_NUM=":99"
SCREEN_RES="1280x800x24"   # Change to match your monitor (e.g. 1920x1080x24)
VNC_PORT="5900"
REMOTE_DEBUG_PORT="9222"
# ─────────────────────────────────────────────────────────────────────────────

export DISPLAY="$DISPLAY_NUM"
LOGDIR="/var/log/zoho-kiosk"
mkdir -p "$LOGDIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGDIR/kiosk.log"; }

# ── Kill any existing instances ───────────────────────────────────────────────
pkill -f "Xvfb $DISPLAY_NUM" 2>/dev/null || true
pkill -f chromium-browser 2>/dev/null || true
pkill -f x11vnc 2>/dev/null || true
pkill fluxbox 2>/dev/null || true
sleep 1

log "Starting Zoho Kiosk..."

# ── Start virtual framebuffer display ────────────────────────────────────────
log "Starting Xvfb virtual display at $DISPLAY_NUM ($SCREEN_RES)..."
Xvfb "$DISPLAY_NUM" -screen 0 "$SCREEN_RES" -ac +extension GLX +render -noreset &
XVFB_PID=$!
sleep 2

if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    log "ERROR: Xvfb failed to start. Check if display $DISPLAY_NUM is already in use."
    exit 1
fi
log "Xvfb started (PID $XVFB_PID)"

# ── Start window manager (needed for proper window behavior) ──────────────────
log "Starting fluxbox window manager..."
fluxbox -display "$DISPLAY_NUM" &>/dev/null &
sleep 1

# ── Start VNC server (for remote viewing/management) ─────────────────────────
log "Starting VNC server on port $VNC_PORT..."
x11vnc \
    -display "$DISPLAY_NUM" \
    -forever \
    -nopw \
    -quiet \
    -port "$VNC_PORT" \
    -logfile "$LOGDIR/vnc.log" &
log "VNC available at: $(hostname -I | awk '{print $1}'):$VNC_PORT (no password)"

# ── Start Chromium in Kiosk mode ─────────────────────────────────────────────
log "Starting Chromium browser at: $ZOHO_KIOSK_URL"

# Clear any stale lock files that prevent Chromium restart
CHROME_PROFILE="/tmp/zoho-kiosk-profile"
mkdir -p "$CHROME_PROFILE"
rm -f "$CHROME_PROFILE/SingletonLock" 2>/dev/null
rm -f "$CHROME_PROFILE/SingletonCookie" 2>/dev/null

chromium-browser \
    --display="$DISPLAY_NUM" \
    --kiosk \
    --no-sandbox \
    --disable-infobars \
    --disable-session-crashed-bubble \
    --disable-restore-session-state \
    --disable-features=TranslateUI,PrivacySandboxSettings4 \
    --no-first-run \
    --noerrdialogs \
    --autoplay-policy=no-user-gesture-required \
    --remote-debugging-port="$REMOTE_DEBUG_PORT" \
    --remote-debugging-address=127.0.0.1 \
    --user-data-dir="$CHROME_PROFILE" \
    --window-size=1280,800 \
    --start-fullscreen \
    --app="$ZOHO_KIOSK_URL" \
    >> "$LOGDIR/chromium.log" 2>&1 &

CHROME_PID=$!
log "Chromium started (PID $CHROME_PID)"
log "Chrome DevTools Protocol at: http://127.0.0.1:$REMOTE_DEBUG_PORT"
log "Check logs at: $LOGDIR/"

# ── Wait and auto-restart Chromium if it crashes ─────────────────────────────
while true; do
    if ! kill -0 "$CHROME_PID" 2>/dev/null; then
        log "WARNING: Chromium crashed or exited. Restarting in 5 seconds..."
        sleep 5
        rm -f "$CHROME_PROFILE/SingletonLock" 2>/dev/null
        chromium-browser \
            --display="$DISPLAY_NUM" \
            --kiosk \
            --no-sandbox \
            --disable-infobars \
            --disable-session-crashed-bubble \
            --disable-restore-session-state \
            --disable-features=TranslateUI,PrivacySandboxSettings4 \
            --no-first-run \
            --noerrdialogs \
            --autoplay-policy=no-user-gesture-required \
            --remote-debugging-port="$REMOTE_DEBUG_PORT" \
            --remote-debugging-address=127.0.0.1 \
            --user-data-dir="$CHROME_PROFILE" \
            --window-size=1280,800 \
            --start-fullscreen \
            --app="$ZOHO_KIOSK_URL" \
            >> "$LOGDIR/chromium.log" 2>&1 &
        CHROME_PID=$!
        log "Chromium restarted (PID $CHROME_PID)"
    fi
    sleep 10
done
