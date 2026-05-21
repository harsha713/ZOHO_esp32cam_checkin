# Zoho Smart Kiosk — Complete Setup Guide
### Ubuntu 24.04 Server + Docker + ESP32-CAM + Dashboard
---

# PART 1: WHAT YOU ARE BUILDING

```
[ESP32-CAM Box at Reception]          [HDMI Monitor at Reception]
  📷 Streams video over WiFi             Shows Zoho Kiosk UI
  🟢 CHECK IN button                     (Chrome browser, full screen)
  🔴 CHECK OUT button
         │ WiFi                                ║ HDMI cable
         ▼                                     ║
[Your Ubuntu 24.04 Server — 3 Docker Containers]
  ├── zoho-kiosk        : Xvfb + Chrome + VNC
  ├── zoho-camera-feed  : ffmpeg pipes ESP32 → /dev/video10
  └── zoho-middleware   : Node.js — buttons→browser, dashboard, event log
         │ HTTPS
         ▼
  [Zoho People Cloud]

[Any LAN device] → http://192.168.1.150:5003 → Live Dashboard
```

**Total cost:** ~₹400–700 (just buttons + enclosure + USB charger — ESP32-CAM you already have)

---

# PART 2: HARDWARE — PARTS & WIRING

## 2.1 Parts List

| Part | Qty | Approx Cost |
|---|---|---|
| ESP32-CAM (AI Thinker) | 1 | ₹0 (you have it) |
| FTDI USB-to-Serial adapter | 1 | ₹150–300 (one-time, for flashing) |
| Momentary push button (green) | 1 | ₹10 |
| Momentary push button (red) | 1 | ₹10 |
| USB 5V ≥1A charger + cable | 1 | ₹150 |
| Small plastic project box | 1 | ₹100–200 |
| Jumper wires | few | ₹30 |
| HDMI monitor (old/spare) | 1 | ₹0 if you have one |
| HDMI cable (long enough) | 1 | ₹200–500 |

## 2.2 Button Wiring (Normal Operation)

No resistors needed — the ESP32 has built-in pull-up resistors.

```
ESP32-CAM Board
┌─────────────────────┐
│                     │
│  GPIO13 ────────────┼──── [GREEN: CHECK IN button] ──── GND
│                     │
│  GPIO15 ────────────┼──── [RED: CHECK OUT button]  ──── GND
│                     │
│  5V     ────────────┼──── USB Charger (+)
│  GND    ────────────┼──── USB Charger (-)
│                     │
│  [OV2640 Camera module on back]
└─────────────────────┘
```

Each button: one leg → GPIO pin, other leg → GND. That's it.

## 2.3 Programming Wiring (FTDI — only during firmware upload)

```
FTDI Adapter          ESP32-CAM
────────────          ─────────
GND        ─────────► GND
3.3V       ─────────► 3.3V  (use 3.3V, NOT 5V during programming)
TX         ─────────► U0R (GPIO3 / RX)
RX         ─────────► U0T (GPIO1 / TX)
                      GPIO0 ──── GND  ← SHORT only during upload, remove after!
```

After upload: **remove the GPIO0→GND wire**, press the RESET button.

## 2.4 Physical Enclosure

```
FRONT:
┌──────────────────────────┐
│  👁  [Camera Lens]        │
│                          │
│  [ ✅  CHECK   IN  ]      │  ← green button
│  [ 🔴  CHECK  OUT  ]      │  ← red button
└──────────────────────────┘
BACK: USB power cable exits here
```

---

# PART 3: STATIC IP FOR ESP32-CAM

**Why you need this:** If the ESP32 uses DHCP, its IP can change each time it powers on. Your server config would need updating every time. A static IP fixes this permanently.

**Best method — Set it in firmware** (already configured in `config.h`):

Open `esp32cam/esp32cam_kiosk/config.h` and edit:

```cpp
#define USE_STATIC_IP  true            // Keep this true

#define STATIC_IP   "192.168.1.151"   // ← CHANGE: pick a free IP
#define GATEWAY_IP  "192.168.1.1"     // ← Your router's IP
#define SUBNET_MASK "255.255.255.0"
#define DNS_IP      "8.8.8.8"
```

**How to pick a safe static IP:**
1. Log into your router (usually http://192.168.1.1)
2. Find DHCP settings → note the DHCP range (e.g. 192.168.1.100 to 192.168.1.200)
3. Pick an IP **outside** that range (e.g. 192.168.1.151)
4. Make sure nothing else on your network uses that IP

After flashing, the ESP32 will **always** come up at `192.168.1.151` — no matter how many times you power it on/off. Your server config never needs to change.

**Backup method — Router DHCP Reservation:**
Even better used together with the firmware static IP. In your router:
1. Find the ESP32-CAM in the connected devices list
2. Click "Reserve IP" or "Static DHCP" → assign it a fixed IP based on its MAC address
3. This ensures the router never hands that IP to another device

---

# PART 4: SERVER SETUP (UBUNTU 24.04)

## 4.1 Copy the Project to Your Server

Your server is reachable via Tailscale at `100.109.145.93`.
The project lives at `/mnt/Amma/ZOHO_smart_checkin` on your PC.

```bash
# Run this on YOUR PC (not the server):
scp -r /mnt/Amma/ZOHO_smart_checkin youruser@100.109.145.93:/opt/zoho-kiosk
```

Replace `youruser` with your actual Linux username on the server
(the same one you use when you `ssh youruser@100.109.145.93`).

Verify it landed on the server:
```bash
ssh youruser@100.109.145.93
ls /opt/zoho-kiosk
# Should show: docker-compose.yml  .env.example  host-setup.sh  kiosk/  middleware/  ...
```

After any code or config change on your PC, re-sync just the changed folder:
```bash
# Re-sync only middleware (e.g. after editing config.json or dashboard.html):
scp -r /mnt/Amma/ZOHO_smart_checkin/middleware youruser@100.109.145.93:/opt/zoho-kiosk/

# Re-sync the whole project:
scp -r /mnt/Amma/ZOHO_smart_checkin/. youruser@100.109.145.93:/opt/zoho-kiosk/
```

Then on the server, rebuild the affected container:
```bash
ssh youruser@100.109.145.93
cd /opt/zoho-kiosk
docker compose up -d --build zoho-middleware   # or whichever changed
```

## 4.2 Install Docker on Ubuntu 24.04

If Docker is not already installed:

```bash
# Add Docker's official apt repo for Ubuntu 24.04 (Noble)
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

# Add yourself to docker group (so you don't need sudo every time)
sudo usermod -aG docker $(whoami)

# Log out and back in for group change to take effect, then verify:
docker --version        # Docker version 24.x or higher
docker compose version  # Docker Compose version v2.x
```

> ⚠️ On Ubuntu 24.04, the command is `docker compose` (space), NOT `docker-compose` (hyphen). The old hyphen version is deprecated.

## 4.3 Host Pre-Setup (Virtual Camera Kernel Module)

This runs **once on the host** — it creates the virtual `/dev/video10` camera device that Docker containers share. This is the only step that can't be containerised.

```bash
cd /opt/zoho-kiosk
bash host-setup.sh
```

The script:
- Installs `v4l2loopback-dkms` via apt
- Loads the kernel module → creates `/dev/video10`
- Persists it across reboots via `/etc/modules-load.d/`
- Adds a udev rule for Docker device access
- Adds your user to the `video` group

Verify it worked:
```bash
v4l2-ctl --list-devices
# Should show: ZohoKioskCam (/dev/video10)
```

> ⚠️ Log out and back in (or reboot) after this step for the `video` group to apply.

## 4.4 Configure Your Settings

```bash
cd /opt/zoho-kiosk
cp .env.example .env
nano .env
```

Set these values:

```bash
ZOHO_KIOSK_URL=https://people.zoho.in/YourActualCompany/kiosk
ESP32_CAM_IP=192.168.1.151   # ← must match STATIC_IP in config.h
SCREEN_RESOLUTION=1280x800x24
TZ=Asia/Kolkata
```

**How to find your Zoho Kiosk URL:**
1. Log into Zoho People as admin
2. Attendance → Kiosk → Open Kiosk
3. Copy the URL from the browser address bar

## 4.5 Open Firewall Ports (if ufw is active)

```bash
sudo ufw allow 5900/tcp comment "Zoho Kiosk VNC"
sudo ufw allow 5003/tcp comment "Zoho Kiosk Dashboard"
sudo ufw reload
sudo ufw status
```

## 4.6 Build and Start the Docker Stack

```bash
cd /opt/zoho-kiosk
docker compose up -d --build
```

First build takes 5–10 minutes (downloads Chrome ~100MB). Subsequent starts are instant.

Check status:
```bash
docker compose ps
```

Expected output:
```
NAME                STATUS          PORTS
zoho-camera-feed    Up
zoho-kiosk          Up (healthy)    0.0.0.0:5900->5900/tcp
zoho-middleware     Up (healthy)    0.0.0.0:5003->5003/tcp
```

View live logs:
```bash
docker compose logs -f                    # all containers
docker compose logs -f zoho-kiosk        # browser only
docker compose logs -f zoho-camera-feed  # camera bridge only
docker compose logs -f zoho-middleware   # middleware/dashboard only
```

---

# PART 5: PORTAINER SETUP

Since you already have Portainer running, deploy as a Stack:

1. Open Portainer → **Stacks** → **+ Add Stack**
2. Name: `zoho-kiosk`
3. Select **Upload** → upload `docker-compose.yml`
4. Scroll to **Environment variables** → click **Load variables from .env file** → upload your `.env`
5. Click **Deploy the stack**

All 3 containers appear in Portainer's Containers view with:
- 🟢 Health indicators
- Live log streaming (Container → Logs tab)
- CPU/RAM stats (Container → Stats tab)
- Restart button per container

To update after config changes: **Stacks → zoho-kiosk → Editor → Update the stack**

---

# PART 6: PROGRAMMING THE ESP32-CAM

## 6.1 Install Arduino IDE

1. Download [Arduino IDE 2.x](https://www.arduino.cc/en/software) and install it

## 6.2 Add ESP32 Board Support

1. File → Preferences → "Additional Boards Manager URLs" → add:
   ```
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
2. Tools → Board → Boards Manager → search `esp32` → install **"esp32 by Espressif Systems"**

## 6.3 Edit config.h — on YOUR PC

> **Where is this file?**
> It's on **your own PC** (not the server, not inside the ESP32) at:
> `/mnt/Amma/ZOHO_smart_checkin/esp32cam/esp32cam_kiosk/config.h`
>
> **Do I flash config.h separately?**
> **No.** `config.h` is a C header file — it is *not* uploaded on its own.
> When Arduino IDE compiles and uploads the `.ino` sketch, it automatically
> includes `config.h` because both files sit in the same folder (`esp32cam_kiosk/`).
> You just edit config.h, open the `.ino` in Arduino IDE, and click Upload. Done.
>
> **How to open and edit it:**
> - Open it in any text editor: VS Code, gedit, nano, Notepad++, etc.
> - **Or** open the `.ino` in Arduino IDE → you'll see a `config.h` tab at the
>   top of the editor → click that tab → edit directly there.

Open `/mnt/Amma/ZOHO_smart_checkin/esp32cam/esp32cam_kiosk/config.h` on your PC and fill in these values:

```cpp
#define WIFI_SSID     "YourWiFiName"
#define WIFI_PASSWORD "YourWiFiPassword"

#define USE_STATIC_IP  true
#define STATIC_IP   "192.168.1.151"   // ← must match ESP32_CAM_IP in your .env file
#define GATEWAY_IP  "192.168.1.1"     // ← your router's IP (usually this)

// Your server's LOCAL network IP (not the Tailscale IP).
// On the server, run: hostname -I
// The server's local IP is: 192.168.1.150
#define SERVER_IP   "192.168.1.150"
#define SERVER_PORT 5003
```

## 6.4 Wire FTDI for Programming (see Part 2.3)

Connect IO0 → GND before plugging FTDI into PC.

## 6.5 Upload Settings in Arduino IDE

| Setting | Value |
|---|---|
| Board | AI Thinker ESP32-CAM |
| Upload Speed | 115200 |
| Flash Mode | DIO |
| Partition Scheme | Huge APP (3MB No OTA/1MB SPIFFS) |
| Port | Your FTDI COM port (e.g. /dev/ttyUSB0 on Linux) |

Click **→ Upload**. When you see `Connecting......`, press and release the RESET button on the ESP32-CAM if it gets stuck.

## 6.6 After Upload

1. **Remove the IO0→GND wire**
2. Press RESET
3. Open Serial Monitor (115200 baud)
4. You should see:
   ```
   === Zoho Kiosk ESP32-CAM ===
   Static IP configured: 192.168.1.151
   WiFi connected!
     IP Address : 192.168.1.151
     Stream URL : http://192.168.1.151/stream
   Setup complete. Streaming and monitoring buttons.
   ```
5. Test stream: open `http://192.168.1.151/stream` in your browser — you should see live video

---

# PART 7: FIRST-TIME CONFIGURATION

## 7.1 Connect VNC to See the Kiosk

1. Download [VNC Viewer](https://www.realvnc.com/en/connect/download/viewer/)
2. Add connection: `192.168.1.150:5900`
   (use the local IP here, not Tailscale — VNC needs low latency)
3. No password
4. You'll see Chrome with the Zoho Kiosk page

## 7.2 Grant Camera Permission (one time only)

In VNC Viewer, Chrome will ask for camera permission. Click **Allow**.
This is saved in the `chrome-profile` Docker volume — it persists across restarts forever.

If it doesn't ask automatically, click the camera icon in Chrome's address bar → select `ZohoKioskCam` → Allow.

## 7.3 Find the Correct Zoho Button CSS Selectors

The middleware needs to know which HTML elements to click in Zoho.

1. In VNC Viewer, right-click the **Check In** button on the Zoho page
2. Click **Inspect**
3. Look at the highlighted element, e.g.:
   ```html
   <button class="checkin-btn" data-action="checkin">Check In</button>
   ```
   The selector is: `[data-action='checkin']` or `.checkin-btn`

4. Update `middleware/config.json`:
   ```json
   "checkin_selectors":  ["[data-action='checkin']", ".checkin-btn"],
   "checkout_selectors": ["[data-action='checkout']", ".checkout-btn"]
   ```

5. Rebuild the middleware container:
   ```bash
   docker compose up -d --build zoho-middleware
   ```
   Or in Portainer: Containers → `zoho-middleware` → Recreate

## 7.4 Test End-to-End

Watch middleware logs and press the CHECK IN button on your ESP32 device:
```bash
docker compose logs -f zoho-middleware
```

Expected log:
```
[INFO ] GET /button/checkin ← 192.168.1.151
[OK   ] CHECK-IN: clicked → [data-action='checkin']
[INFO ] Event saved: checkin at 2026-05-18T15:00:00.000Z
```

And in VNC you'll see Zoho activating the face recognition camera.

---

# PART 8: DASHBOARD

## 8.1 Access

Any device on your LAN (phone, tablet, laptop) can open:
```
http://192.168.1.150:5003
```

You can also reach it from outside your network via Tailscale:
```
http://100.109.145.93:5003
```

No app needed. Any browser works.

## 8.2 What the Dashboard Shows

- **Kiosk Browser** status — is Chrome running and healthy?
- **ESP32-CAM** status — is the camera device reachable?
- **Check-ins today / Check-outs today / Total events** counters
- **Live camera feed** — proxied from ESP32-CAM through the server (no CORS issues)
- **Real-time activity log** — every button press appears instantly via Server-Sent Events
  - Time, date, action (Check In / Check Out), success status, source device IP
- Filter tabs: All / Check-In / Check-Out

## 8.3 Event Log Persistence

Events are stored in `/var/log/zoho-kiosk/events.json` inside the `events-log` Docker volume. They **survive container restarts and rebuilds**. Up to 500 events are kept.

## 8.4 API Endpoints (for custom integrations)

```bash
# All events (JSON)
curl http://192.168.1.150:5003/api/events

# Today's events only
curl "http://192.168.1.150:5003/api/events?date=$(date +%d/%m/%Y)"

# System status
curl http://192.168.1.150:5003/api/status

# Camera stream (MJPEG — open this URL in any browser or in VLC)
http://192.168.1.150:5003/api/camera

# Health check
curl http://192.168.1.150:5003/health
```

---

# PART 9: MANAGEMENT & MAINTENANCE

## Daily Commands

```bash
cd /opt/zoho-kiosk

# Check all containers
docker compose ps

# Restart everything
docker compose restart

# Restart one container
docker compose restart zoho-kiosk
docker compose restart zoho-middleware
docker compose restart zoho-camera-feed

# Live logs
docker compose logs -f
docker compose logs -f zoho-middleware --tail=50

# Shell into a container (debugging)
docker compose exec zoho-middleware sh
docker compose exec zoho-kiosk bash

# Resource usage
docker stats
```

## Updating the Stack

After any code or config change:
```bash
docker compose up -d --build         # rebuild changed images
# OR in Portainer: Stacks → zoho-kiosk → Editor → Update the stack
```

## Simulate Button Presses (Testing)

```bash
# From any machine on LAN (or from the server itself):
curl http://192.168.1.150:5003/button/checkin
curl http://192.168.1.150:5003/button/checkout
```

## After Server Reboot

Docker containers auto-restart (`restart: unless-stopped`).
But v4l2loopback should also auto-load (configured in `/etc/modules-load.d/`).

If the camera feed fails after reboot, manually reload:
```bash
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="ZohoKioskCam" exclusive_caps=1
docker compose restart zoho-camera-feed
```

---

# PART 10: TROUBLESHOOTING

| Problem | Symptom | Fix |
|---|---|---|
| Camera feed exits immediately | Log: `/dev/video10 not found` | Run `bash host-setup.sh` then restart `zoho-camera-feed` |
| VNC shows blank screen | Black screen in VNC Viewer | `docker compose restart zoho-kiosk` |
| Camera black in Zoho | Face recognition not working | Grant camera permission in VNC (Part 7.2) |
| Middleware can't reach Chrome | Log: `CDP error: Connection refused` | Wait 20s for Chrome to start; check `zoho-kiosk` health in Portainer |
| Button does nothing | Log: `selector_not_found` | Find correct CSS selector (Part 7.3), update `config.json`, rebuild middleware |
| ESP32 not connecting to WiFi | Serial: keeps printing `.....` | Check WIFI_SSID / WIFI_PASSWORD in `config.h`; reflash |
| ESP32 gets wrong IP | IP not matching `STATIC_IP` | Check `USE_STATIC_IP true` in config.h; also check router isn't assigning same IP to another device |
| Dashboard shows "Camera offline" | Red badge on dashboard | ESP32-CAM is powered off or IP changed |
| Docker build fails | Error during `docker compose up --build` | Check internet on server: `curl https://google.com` |
| Stack won't start in Portainer | Container keeps restarting | Check container logs in Portainer → Logs tab |
| Chrome crashes in kiosk | Browser keeps restarting | Normal — the entrypoint auto-restarts it; check Zoho URL in `.env` |

## Useful Debug Commands

```bash
# Check virtual camera exists and has data
v4l2-ctl --list-devices
ffplay -f v4l2 /dev/video10         # shows live preview (needs display)

# Check Chrome DevTools is reachable
curl http://localhost:9222/json

# Check ESP32-CAM stream directly
curl http://192.168.1.151/stream --output /tmp/test.jpg

# Check if camera module is loaded
lsmod | grep v4l2loopback

# Check all service logs at once
docker compose logs --tail=20
```

---

# PART 11: DISPLAY OPTIONS AT RECEPTION

### Option A — Long HDMI Cable (Simplest)
Run an HDMI cable from your server to the reception monitor.
Works up to ~10 metres. For longer runs, use an HDMI over Ethernet extender (₹1,500–2,500).
No changes needed to the software.

### Option B — Cheap Android Tablet as Display
Install VNC Viewer on a spare Android tablet.
Set tablet to full-screen, auto-connect to `192.168.1.150:5900`.
Disable auto-lock. Plug it into a charger.
No cable needed — runs over WiFi.

### Option C — Raspberry Pi as Display Terminal (if you have one)
Install `tigervnc-viewer` on Raspberry Pi OS:
```bash
sudo apt install tigervnc-viewer
vncviewer 192.168.1.150:5900 &
```
Set this to auto-run on boot via `/etc/rc.local` or a systemd service.

---

# APPENDIX: BARE-METAL (NON-DOCKER) INSTALLATION

If for any reason you don't want Docker, you can run everything natively on Ubuntu 24.04.

## Install System Packages

```bash
sudo apt-get update
sudo apt-get install -y \
    xvfb fluxbox x11vnc \
    ffmpeg v4l2loopback-dkms v4l2loopback-utils \
    curl git build-essential

# Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

## Install Google Chrome (Ubuntu 24.04)

```bash
# chromium-browser on Ubuntu 24.04 is a snap stub — use Google Chrome directly
wget -q -O /tmp/google-chrome.gpg https://dl.google.com/linux/linux_signing_key.pub
gpg --dearmor < /tmp/google-chrome.gpg | sudo tee /usr/share/keyrings/google-chrome-keyring.gpg > /dev/null
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | sudo tee /etc/apt/sources.list.d/google-chrome.list > /dev/null
sudo apt-get update && sudo apt-get install -y google-chrome-stable
```

## Load Virtual Camera

```bash
sudo modprobe v4l2loopback devices=1 video_nr=10 card_label="ZohoKioskCam" exclusive_caps=1
# Persist:
echo "v4l2loopback" | sudo tee /etc/modules-load.d/v4l2loopback.conf
echo 'options v4l2loopback devices=1 video_nr=10 card_label="ZohoKioskCam" exclusive_caps=1' | sudo tee /etc/modprobe.d/zoho-kiosk-cam.conf
```

## Install Middleware Dependencies

```bash
cd /opt/zoho-kiosk/middleware
npm install
```

## Run with systemd Services

Copy and edit the service files from `server/` and `middleware/`:
```bash
# Replace YOUR_USERNAME and INSTALL_DIR in each .service file, then:
sudo cp server/zoho-kiosk.service /etc/systemd/system/
sudo cp server/zoho-camera-feed.service /etc/systemd/system/
sudo cp middleware/zoho-middleware.service /etc/systemd/system/

sudo systemctl daemon-reload
sudo systemctl enable --now zoho-kiosk zoho-camera-feed zoho-middleware

# Check status
sudo systemctl status zoho-kiosk
journalctl -u zoho-middleware -f
```

> Replace `google-chrome-stable` for `google-chrome` in `server/start-kiosk.sh` if the binary name differs on your install (`which google-chrome-stable`).
