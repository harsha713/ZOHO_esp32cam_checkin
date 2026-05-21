# =============================================================================
# Zoho Kiosk — Kiosk Browser Container
# Base: Ubuntu 24.04
# Contains: Xvfb, Google Chrome, x11vnc, fluxbox
# =============================================================================

FROM ubuntu:24.04

LABEL maintainer="zoho-kiosk"
LABEL description="Headless Chromium kiosk browser with VNC access"

# Avoid interactive prompts during apt installs
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

# ── System dependencies ───────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Virtual display & window manager
    xvfb \
    fluxbox \
    x11vnc \
    # Chrome dependencies
    wget \
    curl \
    gnupg \
    ca-certificates \
    fonts-liberation \
    fonts-noto \
    libasound2t64 \
    libatk-bridge2.0-0t64 \
    libatk1.0-0t64 \
    libatspi2.0-0t64 \
    libcups2t64 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libglib2.0-0t64 \
    libgtk-3-0t64 \
    libnspr4 \
    libnss3 \
    libvulkan1 \
    libx11-6 \
    libx11-xcb1 \
    libxcb-dri3-0 \
    libxcomposite1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    libxss1 \
    libxtst6 \
    xdg-utils \
    # Utilities
    procps \
    && rm -rf /var/lib/apt/lists/*

# ── Install Google Chrome Stable ──────────────────────────────────────────────
# (chromium-browser on Ubuntu 24.04 is a snap stub — doesn't work in Docker)
RUN wget -q -O /tmp/google-chrome.gpg https://dl.google.com/linux/linux_signing_key.pub \
    && gpg --dearmor < /tmp/google-chrome.gpg \
       > /usr/share/keyrings/google-chrome-keyring.gpg \
    && rm /tmp/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-keyring.gpg] \
       http://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# ── Copy entrypoint ───────────────────────────────────────────────────────────
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# ── Ports ─────────────────────────────────────────────────────────────────────
# 5900: VNC (remote viewing/management)
# 9222: Chrome DevTools Protocol (internal — middleware talks to this)
EXPOSE 5900 9222

ENTRYPOINT ["/entrypoint.sh"]
