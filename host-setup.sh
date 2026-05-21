#!/bin/bash
# =============================================================================
# ZOHO SMART KIOSK — Host-Only Pre-Setup Script
# Run this ONCE on your Ubuntu 24.04 server BEFORE starting Docker containers.
# This does the one thing that cannot be containerized: loading the v4l2loopback
# kernel module that creates the virtual camera device (/dev/video10).
#
# Usage: bash host-setup.sh
# =============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[✓]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
die()  { echo -e "${RED}[✗] $1${NC}"; exit 1; }

echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Zoho Kiosk — Ubuntu 24.04 Host Pre-Setup   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════╝${NC}"
echo ""

[[ $EUID -eq 0 ]] && die "Do not run as root. Run as your regular user (with sudo access)."

# ── Step 1: Install v4l2loopback (kernel module) ──────────────────────────────
info "Step 1/4 — Installing v4l2loopback kernel module..."
sudo apt-get update -qq
sudo apt-get install -y v4l2loopback-dkms v4l2loopback-utils linux-headers-$(uname -r)
log "v4l2loopback installed."

# ── Step 2: Load the module now ───────────────────────────────────────────────
info "Step 2/4 — Loading v4l2loopback module..."
if lsmod | grep -q v4l2loopback; then
    warn "v4l2loopback already loaded. Reloading with correct options..."
    sudo modprobe -r v4l2loopback 2>/dev/null || true
fi

sudo modprobe v4l2loopback \
    devices=1 \
    video_nr=10 \
    card_label="ZohoKioskCam" \
    exclusive_caps=1

if [ -e /dev/video10 ]; then
    log "Virtual camera created: /dev/video10"
else
    die "/dev/video10 was not created. Check dmesg for errors: sudo dmesg | tail -20"
fi

# ── Step 3: Persist module across reboots ─────────────────────────────────────
info "Step 3/4 — Persisting v4l2loopback across reboots..."

# Add to /etc/modules-load.d/ (Ubuntu 24.04 style)
sudo tee /etc/modules-load.d/v4l2loopback.conf > /dev/null << 'EOF'
v4l2loopback
EOF

# Set module options
sudo tee /etc/modprobe.d/zoho-kiosk-cam.conf > /dev/null << 'EOF'
options v4l2loopback devices=1 video_nr=10 card_label="ZohoKioskCam" exclusive_caps=1
EOF

log "Module will auto-load on reboot."

# ── Step 4: Make /dev/video10 accessible to Docker ────────────────────────────
info "Step 4/4 — Setting device permissions for Docker..."

# Add current user to 'video' group so Docker containers can access the device
sudo usermod -aG video "$(whoami)"

# Set group permissions on the device now (persisted via udev rule)
sudo tee /etc/udev/rules.d/99-zoho-kiosk-cam.rules > /dev/null << 'EOF'
KERNEL=="video10", GROUP="video", MODE="0660"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

log "Device permissions configured."

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║       Host pre-setup complete! ✓             ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Virtual camera  : ${YELLOW}/dev/video10${NC} ← ready"
echo -e "  Verify with     : ${YELLOW}v4l2-ctl --list-devices${NC}"
echo ""
echo -e "  ${CYAN}Next:${NC} Copy .env.example to .env, edit it, then run:"
echo -e "  ${YELLOW}docker compose up -d${NC}"
echo ""
warn "NOTE: Log out and back in (or reboot) for the 'video' group change to take effect."
warn "      Until then, prefix docker commands with: sudo"
