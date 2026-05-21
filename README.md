# Zoho Smart Check-In Kiosk

> Headless company check-in kiosk using ESP32-CAM + your existing 24/7 server.
> Runs entirely in Docker. No dedicated laptop needed.

---

## Architecture

```
Reception Desk
  +------------------+  +--------------------+
  |  Kiosk Box       |  |  HDMI Monitor      |
  |  ESP32-CAM       |  |                    |
  |  CHECK IN (btn)  |  |  Zoho Kiosk UI     |
  |  CHECK OUT (btn) |  |  (Chrome kiosk)    |
  +------------------+  +--------+-----------+
         | WiFi                   | HDMI
         v                        |
  +-----------------------------------------------+
  |  Server -- Ubuntu 24.04                        |
  |                                                |
  |  HOST: v4l2loopback -> /dev/video10 (virtual)  |
  |                                                |
  |  Docker Stack: zoho-kiosk (host networking)    |
  |    zoho-kiosk        Xvfb + Chrome + VNC:5900  |
  |    zoho-middleware   Node.js + CDP       :5003  |
  |    zoho-camera-feed  ffmpeg -> /dev/video10     |
  |                          | HTTPS                |
  +-----------------------------------------------+
                             v
                    [Zoho People Cloud]
```

---

## File Structure

```
ZOHO_smart_checkin/
  docker-compose.yml       Main Docker stack
  .env.example             Config template (copy to .env)
  host-setup.sh            Run once on host (loads v4l2loopback)

  kiosk/
    Dockerfile             Ubuntu 24.04 + Chrome + Xvfb + VNC
    entrypoint.sh

  camera-feed/
    Dockerfile             Ubuntu 24.04 + ffmpeg
    entrypoint.sh

  middleware/
    Dockerfile             Node.js 20
    middleware.js           Express + Chrome DevTools Protocol
    config.json            Zoho button CSS selectors (edit this)
    dashboard.html         Web dashboard
    package.json

  esp32cam/
    esp32cam_kiosk/
      config.h             WiFi, server IP, GPIO pins (edit this)
      esp32cam_kiosk.ino   Arduino firmware

  server/                  Bare-metal alternative (non-Docker)
    install.sh
    start-kiosk.sh
    feed-camera.sh

  docs/
    FULL_SETUP_GUIDE.md    Complete setup guide
```

---

## Quick Start

```bash
# 1. Copy project to server
ssh slplserver@100.109.145.97 "sudo mkdir -p /opt/zoho-kiosk && sudo chown slplserver:slplserver /opt/zoho-kiosk"
scp -r /mnt/Amma/ZOHO_smart_checkin/. slplserver@100.109.145.97:/opt/zoho-kiosk/

# 2. SSH into server
ssh slplserver@100.109.145.97
cd /opt/zoho-kiosk

# 3. One-time host setup (virtual camera kernel module)
bash host-setup.sh

# 4. Configure
cp .env.example .env
nano .env    # Set ZOHO_KIOSK_URL and ESP32_CAM_IP

# 5. Build and start
docker compose up -d --build

# 6. Flash ESP32-CAM (on your PC)
# Edit esp32cam/config.h, upload via Arduino IDE

# 7. Connect VNC to server-ip:5900, grant camera permission

# 8. Dashboard: http://192.168.1.150:5003
```

---

## Key Commands

```bash
docker compose ps                                  # status
docker compose logs -f zoho-middleware              # logs
docker compose restart zoho-kiosk                   # restart one service
docker compose up -d --build zoho-middleware         # rebuild after changes
curl http://localhost:5003/button/checkin            # test check-in
curl http://localhost:5003/health                    # health check
```

VNC: connect to `192.168.1.150:5900` (password: `zoho1234`)
Dashboard: `http://192.168.1.150:5003`

---

## Documentation

See **[docs/FULL_SETUP_GUIDE.md](docs/FULL_SETUP_GUIDE.md)** for the full walkthrough.

---

## License

MIT
