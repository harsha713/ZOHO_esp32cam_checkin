// =============================================================================
// USER CONFIGURATION — Edit this file before uploading to ESP32-CAM
// =============================================================================
#ifndef CONFIG_H
#define CONFIG_H

// ── WiFi Settings ─────────────────────────────────────────────────────────────
#define WIFI_SSID     "YOUR_WIFI_NAME"       // Your WiFi network name
#define WIFI_PASSWORD "YOUR_WIFI_PASSWORD"   // Your WiFi password

// ── Static IP (HIGHLY RECOMMENDED) ───────────────────────────────────────────
// Set this to true so the ESP32-CAM always gets the same IP, even after reboots.
// This means you never have to update the server config when the device restarts.
//
// How to choose values:
//   STATIC_IP  → Pick any free IP in your network (e.g. 192.168.1.151)
//                 Must be OUTSIDE your router's DHCP range to avoid conflicts!
//                 (Log into your router → DHCP settings → note the DHCP range,
//                  e.g. 192.168.1.100–200. Pick something like 192.168.1.151.)
//   GATEWAY    → Your router's IP (usually 192.168.1.1 or 192.168.0.1)
//   SUBNET     → Almost always 255.255.255.0
//   DNS        → Use 8.8.8.8 (Google) or your router's IP

#define USE_STATIC_IP  true   // ← Set false to use DHCP instead

#define STATIC_IP   "192.168.1.151"   // ← CHANGE THIS (must be outside DHCP range)
#define GATEWAY_IP  "192.168.1.1"     // ← Your router's IP
#define SUBNET_MASK "255.255.255.0"
#define DNS_IP      "8.8.8.8"

// ── Server Settings ───────────────────────────────────────────────────────────
// The LOCAL network IP of your server (NOT the Tailscale IP).
// Your server's local IP is 192.168.1.150
// Your middleware port is 5003
#define SERVER_IP   "192.168.1.150"
#define SERVER_PORT 5003

// ── Button GPIO Pins ──────────────────────────────────────────────────────────
// Connect buttons BETWEEN these GPIO pins and GND.
// The pins use internal pull-up resistors (no resistors needed in hardware).
#define BTN_CHECKIN_PIN  13   // Green button → GPIO 13
#define BTN_CHECKOUT_PIN 15   // Red button   → GPIO 15

// ── Camera Settings ───────────────────────────────────────────────────────────
// Frame size options (comment/uncomment one):
//   FRAMESIZE_QVGA  — 320x240  (fastest, lowest quality)
//   FRAMESIZE_VGA   — 640x480  (recommended, good balance)
//   FRAMESIZE_SVGA  — 800x600
//   FRAMESIZE_XGA   — 1024x768 (might be too slow over WiFi)
#define CAM_FRAME_SIZE  FRAMESIZE_VGA

// JPEG quality: lower = better quality, larger file (range: 4–63)
#define CAM_JPEG_QUALITY 12

// ── Status LED ────────────────────────────────────────────────────────────────
// The built-in LED on most ESP32-CAM boards (used for status blinks)
#define STATUS_LED_PIN 33   // On-board LED (active LOW on AI-Thinker)

// ── Debug ─────────────────────────────────────────────────────────────────────
#define DEBUG_SERIAL true   // Set false to disable Serial output (saves power)

#endif // CONFIG_H
