# Zoho Kiosk -- Node.js Middleware Container

FROM node:20-bookworm-slim

WORKDIR /app

COPY package*.json ./
RUN npm ci --omit=dev && npm cache clean --force

COPY middleware.js ./
COPY config.json ./

RUN mkdir -p /var/log/zoho-kiosk

EXPOSE 5003

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
    CMD node -e "require('http').get('http://localhost:5003/health', r => process.exit(r.statusCode === 200 ? 0 : 1)).on('error', () => process.exit(1))"

CMD ["node", "middleware.js"]
