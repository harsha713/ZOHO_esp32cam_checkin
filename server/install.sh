#!/bin/bash
# =============================================================================
# ZOHO SMART KIOSK — Server Installer
# Run this ONCE on your Ubuntu server as a user with sudo privileges.
# Usage: bash install.sh
# =============================================================================

set -e  # Exit on any error

# ── Colors for pretty output ─────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[✗] ERROR: $1${NC}"; exit 1; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   ZOHO Smart Kiosk — Server Installer   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════╝${NC}"
echo ""

# ── Sanity Checks ─────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] && die "Do NOT run this as root. Run as your normal user with sudo access."
command -v sudo >/dev/null || die "sudo is required."

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CURRENT_USER="$(whoami)"

info "Install directory : $INSTALL_DIR"
info "Running as user   : $CURRENT_USER"
echo ""

# ── Step 1: System packages ───────────────────────────────────────────────────
info "Step 1/7 — Installing system packages..."
sudo apt-get update -qq
sudo apt-get install -y \
    xvfb \
    fluxbox \
    x11vnc \
    chromium-browser \
    ffmpeg \
    v4l2loopback-dkms \
    v4l2loopback-utils \
    curl \
    git \
    build-essential
log "System packages installed."

# ── Step 2: Node.js ───────────────────────────────────────────────────────────
info "Step 2/7 — Installing Node.js 20..."
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
log "Node.js $(node -v) installed."

# ── Step 3: Node middleware dependencies ──────────────────────────────────────
info "Step 3/7 — Installing Node.js middleware dependencies..."
cd "$INSTALL_DIR/middleware"
npm install --silent
log "Node.js dependencies installed."

# ── Step 4: v4l2loopback kernel module ───────────────────────────────────────
info "Step 4/7 — Loading v4l2loopback virtual camera module..."
if ! lsmod | grep -q v4l2loopback; then
    sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="ZohoKioskCam" exclusive_caps=1
fi

# Persist across reboots
if ! grep -q "v4l2loopback" /etc/modules 2>/dev/null; then
    echo "v4l2loopback" | sudo tee -a /etc/modules > /dev/null
fi

MODPROBE_CONF="/etc/modprobe.d/zoho-kiosk-cam.conf"
if [ ! -f "$MODPROBE_CONF" ]; then
    echo 'options v4l2loopback devices=1 video_nr=10 card_label="ZohoKioskCam" exclusive_caps=1' \
        | sudo tee "$MODPROBE_CONF" > /dev/null
fi
log "Virtual camera /dev/video10 ready."

# ── Step 5: Copy and enable systemd services ──────────────────────────────────
info "Step 5/7 — Installing systemd services..."

# Replace placeholder username in service files
for svc_template in "$INSTALL_DIR/server/"*.service "$INSTALL_DIR/middleware/"*.service; do
    [ -f "$svc_template" ] || continue
    svc_name="$(basename "$svc_template")"
    dest="/etc/systemd/system/$svc_name"
    sed "s|YOUR_USERNAME|$CURRENT_USER|g; s|INSTALL_DIR|$INSTALL_DIR|g" \
        "$svc_template" | sudo tee "$dest" > /dev/null
    log "  Installed $svc_name"
done

sudo systemctl daemon-reload

for svc in zoho-kiosk zoho-camera-feed zoho-middleware; do
    sudo systemctl enable "$svc" 2>/dev/null && log "  Enabled $svc" || warn "  $svc not found, skipping"
done

# ── Step 6: Make scripts executable ──────────────────────────────────────────
info "Step 6/7 — Setting permissions..."
chmod +x "$INSTALL_DIR/server/"*.sh 2>/dev/null || true
chmod +x "$INSTALL_DIR/middleware/"*.js 2>/dev/null || true
log "Permissions set."

# ── Step 7: Start services ────────────────────────────────────────────────────
info "Step 7/7 — Starting services..."
for svc in zoho-camera-feed zoho-middleware zoho-kiosk; do
    sudo systemctl start "$svc" 2>/dev/null && log "  Started $svc" || warn "  $svc not started (may need config first)"
done

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║         Installation Complete! ✓         ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}Next steps:${NC}"
echo -e "  1. Edit ${YELLOW}server/start-kiosk.sh${NC} — set your Zoho Kiosk URL"
echo -e "  2. Edit ${YELLOW}server/feed-camera.sh${NC} — set your ESP32-CAM IP"
echo -e "  3. Edit ${YELLOW}middleware/config.json${NC} — set selectors & ESP32-CAM IP"
echo -e "  4. Flash the ESP32-CAM with ${YELLOW}esp32cam/esp32cam_kiosk.ino${NC}"
echo -e "  5. Connect VNC viewer to ${YELLOW}$(hostname -I | awk '{print $1}'):5900${NC} to see the kiosk"
echo ""
