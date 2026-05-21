#!/bin/bash
# Zoho Kiosk -- Container Entrypoint
# Starts: Xvfb -> fluxbox -> x11vnc -> Google Chrome (kiosk mode)

set -e

ZOHO_KIOSK_URL="${ZOHO_KIOSK_URL:-https://people.zoho.in/YourCompany/kiosk}"
SCREEN_RESOLUTION="${SCREEN_RESOLUTION:-1280x800x24}"
CDP_PORT="${CDP_PORT:-9222}"
DISPLAY_NUM=":99"

export DISPLAY="$DISPLAY_NUM"
CHROME_PROFILE="/root/.config/google-chrome/kiosk"
mkdir -p "$CHROME_PROFILE"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [KIOSK] $1"; }

log "Starting kiosk"
log "  URL:        $ZOHO_KIOSK_URL"
log "  Resolution: $SCREEN_RESOLUTION"
log "  CDP port:   $CDP_PORT"

# 1. Virtual display
log "Starting Xvfb on display $DISPLAY_NUM"
Xvfb "$DISPLAY_NUM" \
    -screen 0 "$SCREEN_RESOLUTION" \
    -ac \
    +extension GLX \
    +render \
    -noreset &
XVFB_PID=$!
sleep 2

if ! kill -0 "$XVFB_PID" 2>/dev/null; then
    log "ERROR: Xvfb failed to start"
    exit 1
fi
log "Xvfb started (PID $XVFB_PID)"

# 2. Window manager
log "Starting fluxbox"
fluxbox -display "$DISPLAY_NUM" 2>/dev/null &
sleep 1

# 3. VNC server (port 5900)
VNC_PASSWORD="${VNC_PASSWORD:-zoho1234}"
log "Starting x11vnc on port 5900"
x11vnc \
    -display "$DISPLAY_NUM" \
    -forever \
    -passwd "$VNC_PASSWORD" \
    -rfbport 5900 &
sleep 1
log "VNC ready on port 5900"

# 4. Chrome in kiosk mode
log "Launching Chrome -> $ZOHO_KIOSK_URL"

rm -f "$CHROME_PROFILE/SingletonLock" 2>/dev/null || true
rm -f "$CHROME_PROFILE/SingletonCookie" 2>/dev/null || true

launch_chrome() {
    google-chrome-stable \
        --display="$DISPLAY_NUM" \
        --kiosk \
        --no-sandbox \
        --disable-dev-shm-usage \
        --disable-gpu \
        --disable-software-rasterizer \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-restore-session-state \
        --disable-features=TranslateUI,PrivacySandboxSettings4,AutofillServerCommunication \
        --no-first-run \
        --noerrdialogs \
        --autoplay-policy=no-user-gesture-required \
        --remote-debugging-port="$CDP_PORT" \
        --remote-debugging-address=0.0.0.0 \
        --user-data-dir="$CHROME_PROFILE" \
        --window-size="${SCREEN_RESOLUTION%%x*},${SCREEN_RESOLUTION#*x}" \
        --start-maximized \
        --use-fake-device-for-media-stream=false \
        --app="$ZOHO_KIOSK_URL" 2>&1
}

# 5. Auto-restart Chrome if it crashes
while true; do
    log "Chrome starting..."
    launch_chrome
    log "Chrome exited. Restarting in 5 seconds..."
    rm -f "$CHROME_PROFILE/SingletonLock" 2>/dev/null || true
    sleep 5
done
