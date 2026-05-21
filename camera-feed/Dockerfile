# =============================================================================
# Zoho Kiosk — Camera Feed Bridge Container
# Base: Ubuntu 24.04
# Contains: ffmpeg (reads ESP32-CAM MJPEG → writes to /dev/video10)
# =============================================================================

FROM ubuntu:24.04

LABEL maintainer="zoho-kiosk"
LABEL description="ESP32-CAM MJPEG stream to v4l2loopback virtual camera bridge"

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Kolkata

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    curl \
    v4l2loopback-utils \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
