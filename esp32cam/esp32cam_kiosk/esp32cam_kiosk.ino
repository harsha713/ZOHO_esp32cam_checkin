/**
 * ============================================================================
 * ZOHO SMART KIOSK — ESP32-CAM Firmware
 * ============================================================================
 * Board  : AI Thinker ESP32-CAM (or compatible)
 * Purpose:
 *   1. Stream MJPEG video over WiFi at http://<IP>/stream
 *   2. Monitor two push buttons (Check-In / Check-Out)
 *   3. On button press, send HTTP GET to the Node.js middleware on the server
 *
 * Before uploading:
 *   1. Edit esp32cam_kiosk/config.h with your WiFi & server details
 *   2. Select board: Tools → Board → AI Thinker ESP32-CAM
 *   3. Select Upload Speed: 115200
 *   4. Select Partition Scheme: Huge APP (3MB No OTA/1MB SPIFFS)
 *   5. Connect IO0 → GND for upload, remove AFTER upload
 * ============================================================================
 */

#include "config.h"
#include "esp_camera.h"
#include "esp_http_server.h"
#include <WiFi.h>
#include <WiFiClient.h>

// ─── AI Thinker ESP32-CAM Pin Map ────────────────────────────────────────────
// DO NOT change these — they are hardwired on the PCB
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

// ─── Debug Macro ──────────────────────────────────────────────────────────────
#if DEBUG_SERIAL
  #define DBG(x) Serial.print(x)
  #define DBGLN(x) Serial.println(x)
  #define DBGF(...) Serial.printf(__VA_ARGS__)
#else
  #define DBG(x)
  #define DBGLN(x)
  #define DBGF(...)
#endif

// ─── MJPEG Stream Globals ─────────────────────────────────────────────────────
httpd_handle_t stream_httpd = NULL;

#define PART_BOUNDARY "frame_boundary_zoho_kiosk"
static const char* STREAM_CONTENT_TYPE =
    "multipart/x-mixed-replace;boundary=" PART_BOUNDARY;
static const char* STREAM_BOUNDARY = "\r\n--" PART_BOUNDARY "\r\n";
static const char* STREAM_PART     =
    "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

// ─── Button State ─────────────────────────────────────────────────────────────
volatile bool checkinPressed  = false;
volatile bool checkoutPressed = false;

unsigned long lastCheckinDebounce  = 0;
unsigned long lastCheckoutDebounce = 0;
const unsigned long DEBOUNCE_MS = 200;

// ─── LED Blink Helper ─────────────────────────────────────────────────────────
void blinkLED(int times, int onMs = 100, int offMs = 100) {
  for (int i = 0; i < times; i++) {
    digitalWrite(STATUS_LED_PIN, LOW);  // Active LOW
    delay(onMs);
    digitalWrite(STATUS_LED_PIN, HIGH);
    delay(offMs);
  }
}

// ─── Camera Initialization ───────────────────────────────────────────────────
bool initCamera() {
  camera_config_t cfg;
  cfg.ledc_channel = LEDC_CHANNEL_0;
  cfg.ledc_timer   = LEDC_TIMER_0;
  cfg.pin_d0       = Y2_GPIO_NUM;
  cfg.pin_d1       = Y3_GPIO_NUM;
  cfg.pin_d2       = Y4_GPIO_NUM;
  cfg.pin_d3       = Y5_GPIO_NUM;
  cfg.pin_d4       = Y6_GPIO_NUM;
  cfg.pin_d5       = Y7_GPIO_NUM;
  cfg.pin_d6       = Y8_GPIO_NUM;
  cfg.pin_d7       = Y9_GPIO_NUM;
  cfg.pin_xclk     = XCLK_GPIO_NUM;
  cfg.pin_pclk     = PCLK_GPIO_NUM;
  cfg.pin_vsync    = VSYNC_GPIO_NUM;
  cfg.pin_href     = HREF_GPIO_NUM;
  cfg.pin_sscb_sda = SIOD_GPIO_NUM;
  cfg.pin_sscb_scl = SIOC_GPIO_NUM;
  cfg.pin_pwdn     = PWDN_GPIO_NUM;
  cfg.pin_reset    = RESET_GPIO_NUM;
  cfg.xclk_freq_hz = 20000000;
  cfg.pixel_format = PIXFORMAT_JPEG;
  cfg.frame_size   = CAM_FRAME_SIZE;
  cfg.jpeg_quality = CAM_JPEG_QUALITY;
  cfg.fb_count     = 2;  // Double buffering for smoother streaming

  esp_err_t err = esp_camera_init(&cfg);
  if (err != ESP_OK) {
    DBGF("Camera init failed: 0x%x\n", err);
    return false;
  }

  // Optimize sensor settings for indoor lighting
  sensor_t* s = esp_camera_sensor_get();
  if (s) {
    s->set_brightness(s, 1);       // Slightly brighter
    s->set_contrast(s, 0);
    s->set_saturation(s, 0);
    s->set_special_effect(s, 0);   // No special effect
    s->set_whitebal(s, 1);         // Auto white balance ON
    s->set_awb_gain(s, 1);
    s->set_wb_mode(s, 0);          // Auto WB mode
    s->set_exposure_ctrl(s, 1);    // Auto exposure ON
    s->set_aec2(s, 0);
    s->set_gain_ctrl(s, 1);        // Auto gain ON
    s->set_agc_gain(s, 0);
    s->set_gainceiling(s, (gainceiling_t)0);
    s->set_bpc(s, 0);
    s->set_wpc(s, 1);
    s->set_raw_gma(s, 1);
    s->set_lenc(s, 1);
    s->set_hmirror(s, 0);
    s->set_vflip(s, 0);
    s->set_dcw(s, 1);
    s->set_colorbar(s, 0);
  }

  DBGLN("Camera initialized successfully.");
  return true;
}

// ─── MJPEG Stream HTTP Handler ────────────────────────────────────────────────
esp_err_t streamHandler(httpd_req_t* req) {
  camera_fb_t* fb    = NULL;
  esp_err_t    res   = ESP_OK;
  size_t       jpgLen = 0;
  uint8_t*     jpgBuf = NULL;
  char         partBuf[64];

  // Set response as multipart stream
  res = httpd_resp_set_type(req, STREAM_CONTENT_TYPE);
  if (res != ESP_OK) return res;

  // Disable Nagle's algorithm for lower latency
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "X-Framerate", "15");

  DBGLN("Client connected to /stream");

  while (true) {
    fb = esp_camera_fb_get();
    if (!fb) {
      DBGLN("Camera capture failed");
      res = ESP_FAIL;
    } else {
      if (fb->format != PIXFORMAT_JPEG) {
        // Convert to JPEG if not already
        bool ok = frame2jpg(fb, CAM_JPEG_QUALITY, &jpgBuf, &jpgLen);
        esp_camera_fb_return(fb);
        fb = NULL;
        if (!ok) {
          DBGLN("JPEG conversion failed");
          res = ESP_FAIL;
        }
      } else {
        jpgLen = fb->len;
        jpgBuf = fb->buf;
      }
    }

    if (res == ESP_OK) {
      // Send multipart boundary
      res = httpd_resp_send_chunk(req, STREAM_BOUNDARY, strlen(STREAM_BOUNDARY));
    }
    if (res == ESP_OK) {
      // Send JPEG part header
      size_t hlen = snprintf(partBuf, 64, STREAM_PART, jpgLen);
      res = httpd_resp_send_chunk(req, partBuf, hlen);
    }
    if (res == ESP_OK) {
      // Send JPEG data
      res = httpd_resp_send_chunk(req, (const char*)jpgBuf, jpgLen);
    }

    // Free frame buffer
    if (fb) {
      esp_camera_fb_return(fb);
      fb     = NULL;
      jpgBuf = NULL;
    } else if (jpgBuf) {
      free(jpgBuf);
      jpgBuf = NULL;
    }

    if (res != ESP_OK) {
      DBGLN("Stream client disconnected.");
      break;
    }
  }

  return res;
}

// ─── Root / Info Handler ──────────────────────────────────────────────────────
esp_err_t rootHandler(httpd_req_t* req) {
  char buf[256];
  snprintf(buf, sizeof(buf),
    "Zoho Kiosk ESP32-CAM\n"
    "Stream: http://%s/stream\n"
    "Buttons: GPIO%d (Check-In), GPIO%d (Check-Out)\n",
    WiFi.localIP().toString().c_str(),
    BTN_CHECKIN_PIN, BTN_CHECKOUT_PIN
  );
  httpd_resp_send(req, buf, strlen(buf));
  return ESP_OK;
}

// ─── Start HTTP Server ────────────────────────────────────────────────────────
void startStreamServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port   = 80;
  config.max_uri_handlers = 4;

  httpd_uri_t streamUri = {
    .uri      = "/stream",
    .method   = HTTP_GET,
    .handler  = streamHandler,
    .user_ctx = NULL
  };
  httpd_uri_t rootUri = {
    .uri      = "/",
    .method   = HTTP_GET,
    .handler  = rootHandler,
    .user_ctx = NULL
  };

  if (httpd_start(&stream_httpd, &config) == ESP_OK) {
    httpd_register_uri_handler(stream_httpd, &streamUri);
    httpd_register_uri_handler(stream_httpd, &rootUri);
    DBGLN("HTTP stream server started.");
  } else {
    DBGLN("ERROR: Failed to start HTTP server!");
  }
}

// ─── Send Button Press to Server ──────────────────────────────────────────────
void sendButtonPress(const char* action) {
  DBGF("Sending button press: %s\n", action);
  blinkLED(1, 50, 50);

  WiFiClient client;
  if (!client.connect(SERVER_IP, SERVER_PORT)) {
    DBGLN("ERROR: Could not connect to middleware server!");
    blinkLED(3, 50, 50);  // 3 fast blinks = error
    return;
  }

  // Send HTTP GET request
  String request = String("GET /button/") + action +
                   " HTTP/1.1\r\nHost: " + SERVER_IP +
                   "\r\nConnection: close\r\n\r\n";
  client.print(request);

  // Wait for response (up to 2 seconds)
  unsigned long timeout = millis();
  while (client.available() == 0) {
    if (millis() - timeout > 2000) {
      DBGLN("Timeout waiting for server response");
      client.stop();
      return;
    }
  }

  // Read and log the response
  String response = "";
  while (client.available()) {
    response += (char)client.read();
  }
  client.stop();

  // Check if server returned success
  if (response.indexOf("200 OK") >= 0) {
    DBGF("Server acknowledged: %s\n", action);
    blinkLED(2, 100, 50);  // 2 blinks = success
  } else {
    DBGLN("Server returned unexpected response.");
    blinkLED(3, 50, 50);
  }
}

// ─── WiFi Reconnect ───────────────────────────────────────────────────────────
void ensureWiFiConnected() {
  if (WiFi.status() != WL_CONNECTED) {
    DBGLN("WiFi disconnected, reconnecting...");
    WiFi.disconnect();
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

    int attempts = 0;
    while (WiFi.status() != WL_CONNECTED && attempts < 20) {
      delay(500);
      DBG(".");
      attempts++;
    }
    DBGLN("");

    if (WiFi.status() == WL_CONNECTED) {
      DBGF("Reconnected. IP: %s\n", WiFi.localIP().toString().c_str());
    } else {
      DBGLN("Reconnect failed. Will retry...");
    }
  }
}

// ─── SETUP ────────────────────────────────────────────────────────────────────
void setup() {
#if DEBUG_SERIAL
  Serial.begin(115200);
  delay(100);
  DBGLN("\n\n=== Zoho Kiosk ESP32-CAM ===");
#endif

  // LED setup
  pinMode(STATUS_LED_PIN, OUTPUT);
  digitalWrite(STATUS_LED_PIN, HIGH); // OFF (active LOW)

  // Button setup — use internal pull-up resistors (buttons connect pin to GND)
  pinMode(BTN_CHECKIN_PIN,  INPUT_PULLUP);
  pinMode(BTN_CHECKOUT_PIN, INPUT_PULLUP);
  DBGF("Buttons on GPIO%d (Check-In) and GPIO%d (Check-Out)\n",
       BTN_CHECKIN_PIN, BTN_CHECKOUT_PIN);

  // Initialize camera
  if (!initCamera()) {
    DBGLN("FATAL: Camera init failed. Check module and connections.");
    // Blink rapidly forever to signal error
    while (true) { blinkLED(10, 50, 50); delay(1000); }
  }

  // Connect to WiFi
  DBGF("Connecting to WiFi: %s\n", WIFI_SSID);
  WiFi.mode(WIFI_STA);

#if USE_STATIC_IP
  // Apply static IP — the device will ALWAYS get this IP regardless of DHCP.
  // This means the server config (ESP32_CAM_IP) never needs to change.
  IPAddress ip, gw, sn, dns;
  ip.fromString(STATIC_IP);
  gw.fromString(GATEWAY_IP);
  sn.fromString(SUBNET_MASK);
  dns.fromString(DNS_IP);
  WiFi.config(ip, gw, sn, dns);
  DBGF("Static IP configured: %s\n", STATIC_IP);
#else
  DBGLN("Using DHCP (dynamic IP — check router for assigned IP)");
#endif

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  WiFi.setSleep(false); // Disable WiFi sleep for lower latency

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 30) {
    delay(500);
    DBG(".");
    attempts++;
  }
  DBGLN("");

  if (WiFi.status() != WL_CONNECTED) {
    DBGLN("FATAL: Could not connect to WiFi. Check SSID/password in config.h");
    while (true) { blinkLED(5, 200, 100); delay(2000); }
  }

  DBGLN("WiFi connected!");
  DBGF("  IP Address : %s\n", WiFi.localIP().toString().c_str());
  DBGF("  Signal     : %d dBm\n", WiFi.RSSI());
  DBGF("  Stream URL : http://%s/stream\n", WiFi.localIP().toString().c_str());

  // Start HTTP streaming server
  startStreamServer();

  // Ready — 3 slow blinks
  blinkLED(3, 300, 200);
  DBGLN("Setup complete. Streaming and monitoring buttons.");
}

// ─── LOOP ─────────────────────────────────────────────────────────────────────
void loop() {
  // Ensure WiFi stays connected
  ensureWiFiConnected();

  // ── Check-In Button ─────────────────────────────────────────────────────────
  if (digitalRead(BTN_CHECKIN_PIN) == LOW) {
    unsigned long now = millis();
    if (now - lastCheckinDebounce > DEBOUNCE_MS) {
      lastCheckinDebounce = now;
      DBGLN("CHECK-IN button pressed!");
      sendButtonPress("checkin");
      // Wait for button release before allowing another press
      while (digitalRead(BTN_CHECKIN_PIN) == LOW) { delay(10); }
    }
  }

  // ── Check-Out Button ────────────────────────────────────────────────────────
  if (digitalRead(BTN_CHECKOUT_PIN) == LOW) {
    unsigned long now = millis();
    if (now - lastCheckoutDebounce > DEBOUNCE_MS) {
      lastCheckoutDebounce = now;
      DBGLN("CHECK-OUT button pressed!");
      sendButtonPress("checkout");
      while (digitalRead(BTN_CHECKOUT_PIN) == LOW) { delay(10); }
    }
  }

  delay(10); // Small yield to let background tasks (WiFi, HTTP) run
}
