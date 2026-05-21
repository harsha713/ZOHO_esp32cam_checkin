'use strict';

const express           = require('express');
const CDP               = require('chrome-remote-interface');
const fs                = require('fs');
const path              = require('path');
const http              = require('http');
const { EventEmitter }  = require('events');

// ─── Config ───────────────────────────────────────────────────────────────────
const configPath = path.join(__dirname, 'config.json');
if (!fs.existsSync(configPath)) { console.error('[ERROR] config.json not found.'); process.exit(1); }
const config = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

const PORT       = parseInt(process.env.MIDDLEWARE_PORT) || config.server.port || 3001;
const HOST       = config.server.host || '0.0.0.0';
const CDP_HOST   = process.env.CDP_HOST  || config.chrome_devtools.host || '127.0.0.1';
const CDP_PORT   = parseInt(process.env.CDP_PORT)  || config.chrome_devtools.port || 9222;
const ESP32_IP   = process.env.ESP32_CAM_IP || config.esp32cam.ip;
const ESP32_PORT = config.esp32cam.stream_port || 80;
const ESP32_PATH = config.esp32cam.stream_path || '/stream';

// ─── Logging ──────────────────────────────────────────────────────────────────
const LOGDIR = process.env.LOG_DIR || '/var/log/zoho-kiosk';
try { fs.mkdirSync(LOGDIR, { recursive: true }); } catch (_) {}
const logStream = fs.createWriteStream(path.join(LOGDIR, 'middleware.log'), { flags: 'a' });

function log(level, msg) {
  const line = `[${new Date().toISOString()}] [${level.padEnd(5)}] ${msg}`;
  console.log(line);
  logStream.write(line + '\n');
}
const L = { info: m => log('INFO', m), warn: m => log('WARN', m), error: m => log('ERROR', m), ok: m => log('OK', m) };

// ─── Event Store ──────────────────────────────────────────────────────────────
const EVENTS_FILE = path.join(LOGDIR, 'events.json');
const MAX_EVENTS  = 500;
const eventBus    = new EventEmitter();
eventBus.setMaxListeners(50);

function loadEvents() {
  try { if (fs.existsSync(EVENTS_FILE)) return JSON.parse(fs.readFileSync(EVENTS_FILE, 'utf-8')); }
  catch (e) { L.warn(`Failed to load events: ${e.message}`); }
  return [];
}

function saveEvent(event) {
  const events  = loadEvents();
  const trimmed = [event, ...events].slice(0, MAX_EVENTS);
  try { fs.writeFileSync(EVENTS_FILE, JSON.stringify(trimmed, null, 2)); } catch (e) { L.warn(`Save event failed: ${e.message}`); }
  eventBus.emit('event', event);
  return event;
}

function makeEvent(type, sourceIp, success, detail) {
  const now = new Date();
  return {
    id:        `${Date.now()}-${Math.random().toString(36).substr(2, 5)}`,
    type,
    timestamp: now.toISOString(),
    date:      now.toLocaleDateString('en-IN'),
    time:      now.toLocaleTimeString('en-IN', { hour12: true }),
    success,
    detail,
    source_ip: sourceIp,
  };
}

// ─── CDP Button Clicker ───────────────────────────────────────────────────────
async function clickButton(selectors, label) {
  let client;
  try {
    client = await CDP({ host: CDP_HOST, port: CDP_PORT });
    const { Runtime } = client;
    const expr = `(function(){const s=${JSON.stringify(selectors)};for(const sel of s){const el=document.querySelector(sel);if(el){el.click();return'clicked:'+sel;}}return'not_found';})()`;
    const { result } = await Runtime.evaluate({ expression: expr, returnByValue: true });
    if (result.value === 'not_found') { L.warn(`${label}: no selector matched. Tried: ${selectors.join(', ')}`); return { success: false, detail: 'selector_not_found' }; }
    L.ok(`${label}: ${result.value}`);
    return { success: true, detail: result.value };
  } catch (err) { L.error(`${label} CDP error: ${err.message}`); return { success: false, detail: err.message }; }
  finally { if (client) { try { await client.close(); } catch (_) {} } }
}

// ─── Express ──────────────────────────────────────────────────────────────────
const app = express();
app.use(express.json());
app.use((req, _res, next) => { if (req.path !== '/api/events/stream') L.info(`${req.method} ${req.path} ← ${req.ip}`); next(); });

// ── Dashboard UI ──────────────────────────────────────────────────────────────
app.get('/', (_req, res) => res.sendFile(path.join(__dirname, 'dashboard.html')));

// ── Camera stream proxy ───────────────────────────────────────────────────────
// Proxies ESP32-CAM MJPEG stream so LAN browsers can see it without CORS issues
app.get('/api/camera', (req, res) => {
  const camReq = http.get(`http://${ESP32_IP}:${ESP32_PORT}${ESP32_PATH}`, { timeout: 5000 }, camRes => {
    res.setHeader('Content-Type',  camRes.headers['content-type'] || 'multipart/x-mixed-replace');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Access-Control-Allow-Origin', '*');
    camRes.pipe(res);
  });
  camReq.on('error', () => { if (!res.headersSent) res.status(503).json({ error: 'Camera offline' }); });
  req.on('close', () => camReq.destroy());
});

// ── Events REST ───────────────────────────────────────────────────────────────
app.get('/api/events', (req, res) => {
  const limit  = parseInt(req.query.limit) || 100;
  const date   = req.query.date;
  let events   = loadEvents();
  if (date) events = events.filter(e => e.date === date);
  res.json(events.slice(0, limit));
});

// ── Events SSE (real-time push to dashboard) ──────────────────────────────────
app.get('/api/events/stream', (req, res) => {
  res.setHeader('Content-Type',  'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection',    'keep-alive');
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.flushHeaders();

  const hb      = setInterval(() => res.write(': heartbeat\n\n'), 20000);
  const onEvent = e => res.write(`data: ${JSON.stringify(e)}\n\n`);
  eventBus.on('event', onEvent);
  req.on('close', () => { clearInterval(hb); eventBus.off('event', onEvent); });
});

// ── Status ────────────────────────────────────────────────────────────────────
app.get('/api/status', async (req, res) => {
  let browserOk = false;
  try { const t = await CDP.List({ host: CDP_HOST, port: CDP_PORT }); browserOk = t.length > 0; } catch (_) {}

  let cameraOk = false;
  await new Promise(resolve => {
    const r = http.get(`http://${ESP32_IP}:${ESP32_PORT}/`, { timeout: 2000 }, () => { cameraOk = true; r.destroy(); resolve(); });
    r.on('error', resolve); r.on('timeout', () => { r.destroy(); resolve(); });
  });

  const today      = new Date().toLocaleDateString('en-IN');
  const all        = loadEvents();
  const todayEvts  = all.filter(e => e.date === today);

  res.json({
    middleware:       true,
    browser_ok:       browserOk,
    camera_ok:        cameraOk,
    esp32_ip:         ESP32_IP,
    time:             new Date().toISOString(),
    today_checkins:   todayEvts.filter(e => e.type === 'checkin'  && e.success).length,
    today_checkouts:  todayEvts.filter(e => e.type === 'checkout' && e.success).length,
    total_events:     all.length,
  });
});

// ── Button handlers ───────────────────────────────────────────────────────────
app.get('/button/checkin', async (req, res) => {
  L.info('>>> CHECK-IN pressed <<<');
  const r = await clickButton(config.zoho_kiosk.checkin_selectors, 'CHECK-IN');
  res.json({ ...r, event: saveEvent(makeEvent('checkin', req.ip, r.success, r.detail)) });
});

app.get('/button/checkout', async (req, res) => {
  L.info('>>> CHECK-OUT pressed <<<');
  const r = await clickButton(config.zoho_kiosk.checkout_selectors, 'CHECK-OUT');
  res.json({ ...r, event: saveEvent(makeEvent('checkout', req.ip, r.success, r.detail)) });
});

// ── Health ────────────────────────────────────────────────────────────────────
app.get('/health', async (_req, res) => {
  let browserOk = false;
  try { const t = await CDP.List({ host: CDP_HOST, port: CDP_PORT }); browserOk = t.length > 0; } catch (_) {}
  res.json({ status: 'ok', time: new Date().toISOString(), browser_connected: browserOk });
});

app.use((req, res) => res.status(404).json({ error: 'Not found', path: req.path }));

// ─── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, HOST, () => {
  L.info('='.repeat(55));
  L.info('Zoho Kiosk Middleware + Dashboard');
  L.info(`  Dashboard  → http://192.168.1.150:${PORT}/`);
  L.info(`  Dashboard  → http://100.109.145.93:${PORT}/ (via Tailscale)`);
  L.info(`  Camera     → http://192.168.1.150:${PORT}/api/camera`);
  L.info(`  Events     → http://192.168.1.150:${PORT}/api/events`);
  L.info(`  CDP target → ${CDP_HOST}:${CDP_PORT}`);
  L.info(`  ESP32-CAM  → ${ESP32_IP}:${ESP32_PORT}${ESP32_PATH}`);
  L.info(`  Mode       → ${process.env.CDP_HOST ? 'Docker' : 'Bare-metal'}`);
  L.info('='.repeat(55));
});

process.on('SIGTERM', () => { L.info('Shutdown.'); process.exit(0); });
process.on('SIGINT',  () => { L.info('Shutdown.'); process.exit(0); });
