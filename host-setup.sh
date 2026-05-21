#!/bin/bash
# Zoho Kiosk -- Host Pre-Setup
# Run once on Ubuntu 24.04 before starting Docker containers.
# Loads the v4l2loopback kernel module to create /dev/video10.
#
# Usage: bash host-setup.sh

set -e

log()  { echo "[OK]  $1"; }
info() { echo "[..] $1"; }
warn() { echo "[!!] $1"; }
die()  { echo "[ERR] $1"; exit 1; }

echo ""
echo "Zoho Kiosk -- Host Pre-Setup"
echo ""

[[ $EUID -eq 0 ]] && die "Do not run as root. Run as your regular user (with sudo access)."

# Step 1: Install v4l2loopback
info "Step 1/4 -- Installing v4l2loopback kernel module..."
sudo apt-get update -qq
sudo apt-get install -y v4l2loopback-dkms v4l2loopback-utils linux-headers-$(uname -r)
log "v4l2loopback installed."

# Step 2: Load the module
info "Step 2/4 -- Loading v4l2loopback module..."
if lsmod | grep -q v4l2loopback; then
    warn "v4l2loopback already loaded. Reloading..."
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
    die "/dev/video10 was not created. Check: sudo dmesg | tail -20"
fi

# Step 3: Persist across reboots
info "Step 3/4 -- Persisting module across reboots..."

sudo tee /etc/modules-load.d/v4l2loopback.conf > /dev/null << 'EOF'
v4l2loopback
EOF

sudo tee /etc/modprobe.d/zoho-kiosk-cam.conf > /dev/null << 'EOF'
options v4l2loopback devices=1 video_nr=10 card_label="ZohoKioskCam" exclusive_caps=1
EOF

log "Module will auto-load on reboot."

# Step 4: Device permissions for Docker
info "Step 4/4 -- Setting device permissions..."

sudo usermod -aG video "$(whoami)"

sudo tee /etc/udev/rules.d/99-zoho-kiosk-cam.rules > /dev/null << 'EOF'
KERNEL=="video10", GROUP="video", MODE="0660"
EOF

sudo udevadm control --reload-rules
sudo udevadm trigger

log "Device permissions configured."

echo ""
echo "Host pre-setup complete."
echo "  Virtual camera: /dev/video10"
echo "  Verify: v4l2-ctl --list-devices"
echo ""
echo "Next: cp .env.example .env && nano .env && docker compose up -d --build"
echo ""
echo "NOTE: Log out and back in (or reboot) for the 'video' group change to take effect."
