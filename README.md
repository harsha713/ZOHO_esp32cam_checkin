# Zoho Smart Check-In Kiosk

> **Headless company check-in kiosk using ESP32-CAM + your existing 24/7 server.**
> Runs entirely in Docker. No dedicated laptop needed. Cost: ~₹400–700 + a monitor.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│  Reception Desk                              │
│                                             │
│  ┌────────────────┐  ┌──────────────────┐   │
│  │  Kiosk Box     │  │  HDMI Monitor    │   │
│  │  📷 ESP32-CAM  │  │                  │   │
│  │  🟢 CHECK IN   │  │  Zoho Kiosk UI   │   │
│  │  🔴 CHECK OUT  │  │  (Chrome kiosk)  │   │
│  └────────────────┘  └────────╥─────────┘   │
│         │ WiFi                ║ HDMI         │
└─────────┼──────────────────── ╫─────────────┘
          │                     ║
          ▼                     ║
┌─────────────────────────────────────────────┐
│  Your Server — Ubuntu 24.04                 │
│                                             │
│  ┌─── HOST ───────────────────────────────┐ │
│  │  v4l2loopback → /dev/video10 (virtual) │ │
│  └───────────────────────────────────────┬┘ │
│                                          │   │
│  ┌─── Docker Stack: zoho-kiosk ──────────┤   │
│  │                                       │   │
│  │  zoho-kiosk ──────────────────────────┘   │
│  │    Xvfb :99 + Google Chrome (kiosk)       │
│  │    x11vnc :5900 (remote management)       │
│  │                                           │
│  │  zoho-middleware                          │
│  │    Node.js → CDP → Chrome button clicks   │
│  │    HTTP :3001 ← ESP32 button presses      │
│  │                                           │
│  │  zoho-camera-feed                         │
│  │    ffmpeg: ESP32-CAM → /dev/video10       │
│  │                                           │
│  └───────────────────────────────────────────┘
│                      │ HTTPS
└──────────────────────┼──────────────────────┘
                       ▼
              [Zoho People Cloud]
```

---

## File Structure

```
ZOHO_smart_checkin/
├── docker-compose.yml          ← Main Docker stack (Portainer-compatible)
├── .env.example                ← Config template (copy to .env and edit)
├── host-setup.sh               ← Run ONCE on host to load v4l2loopback kernel module
│
├── kiosk/                      ← Browser container
│   ├── Dockerfile              ← Ubuntu 24.04 + Google Chrome + Xvfb + VNC
│   └── entrypoint.sh
│
├── camera-feed/                ← Camera bridge container
│   ├── Dockerfile              ← Ubuntu 24.04 + ffmpeg
│   └── entrypoint.sh
│
├── middleware/                 ← Button→browser bridge container
│   ├── Dockerfile              ← Node.js 20
│   ├── middleware.js           ← Express + Chrome DevTools Protocol
│   ├── config.json             ← Zoho button CSS selectors (edit this!)
│   └── package.json
│
├── esp32cam/
│   └── esp32cam_kiosk/
│       ├── config.h            ← WiFi, server IP, GPIO pins (EDIT THIS)
│       └── esp32cam_kiosk.ino  ← Arduino firmware
│
├── server/                     ← Bare-metal alternative (non-Docker)
│   ├── install.sh
│   ├── start-kiosk.sh
│   └── feed-camera.sh
│
└── docs/
    ├── docker-guide.md         ← Full Docker + Portainer setup guide ← START HERE
    ├── setup-guide.md          ← Bare-metal alternative guide
    └── wiring-diagram.md       ← ESP32-CAM circuit diagrams + parts list
```

---

## Quick Start (Docker)

```bash
# 1. Copy project to your server via Tailscale (run on YOUR PC):
scp -r /mnt/Amma/ZOHO_smart_checkin youruser@100.109.145.93:/opt/zoho-kiosk

# 2. SSH into server
ssh youruser@100.109.145.93

# 3. One-time host setup (loads virtual camera kernel module)
cd /opt/zoho-kiosk
bash host-setup.sh

# 4. Configure
cp .env.example .env
nano .env           # Set ZOHO_KIOSK_URL and ESP32_CAM_IP

# 5. Build and start
docker compose up -d --build

# 6. Flash ESP32-CAM
# Edit esp32cam/config.h → upload via Arduino IDE

# 7. Watch logs
docker compose logs -f

# 8. VNC to server-ip:5900 → grant camera permission in Chrome

# 9. Open dashboard from any LAN device:
#    http://100.109.145.93:3001
```

---

## Portainer

Load `docker-compose.yml` as a new **Stack** in Portainer.
Add your `.env` variables in the Stack environment section.
All 3 containers will appear with health indicators and live logs.

---

## Key Commands

```bash
# Status
docker compose ps

# Logs
docker compose logs -f zoho-kiosk
docker compose logs -f zoho-camera-feed
docker compose logs -f zoho-middleware

# Restart one service
docker compose restart zoho-kiosk

# Rebuild after changes
docker compose up -d --build zoho-middleware

# Test buttons manually
curl http://localhost:5003/button/checkin
curl http://localhost:5003/button/checkout

# Health check
curl http://localhost:5003/health

# VNC (remote kiosk view — use local IP for best performance)
# Connect VNC Viewer to: 192.168.1.150:5900

# Dashboard (any LAN device)
# http://192.168.1.150:5003
# (or via Tailscale: http://100.109.145.93:5003)
```

---

## Documentation

→ **[docs/FULL_SETUP_GUIDE.md](docs/FULL_SETUP_GUIDE.md)** — the only guide you need

---

## License

MIT — Use freely for your company.

