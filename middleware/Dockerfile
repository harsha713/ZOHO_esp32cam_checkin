# =============================================================================
# Zoho Kiosk — Node.js Middleware Container
# Base: Node.js 20 on Debian Bookworm Slim
# =============================================================================

FROM node:20-bookworm-slim

LABEL maintainer="zoho-kiosk"
LABEL description="Button-press to browser-click bridge via Chrome DevTools Protocol"

WORKDIR /app

# Install production dependencies first (layer cached unless package.json changes)
COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

# Copy application source
COPY middleware.js ./
COPY config.json ./

# Create log directory
RUN mkdir -p /var/log/zoho-kiosk

EXPOSE 3001

# Health check — the middleware exposes a /health endpoint
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:3001/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "middleware.js"]
