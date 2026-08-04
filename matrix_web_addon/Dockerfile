# Global ARGs must be declared before any FROM to be available
# in all build stages. HA Supervisor overrides BUILD_FROM at build time.
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24
ARG ELEMENT_WEB_VERSION=v1.12.24

# ──────────────────────────────────────────────
# Stage 1: Build Element Web from source
# ──────────────────────────────────────────────
FROM node:20-bookworm AS builder

RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

# Clone the specific release tag (shallow clone for speed)
RUN git clone --depth 1 --branch ${ELEMENT_WEB_VERSION} \
        https://github.com/element-hq/element-web.git .

# Install dependencies and build
# Element uses npm; the build produces static files in webapp/
RUN npm install --legacy-peer-deps
RUN npm run build

# ──────────────────────────────────────────────
# Stage 2: Runtime — HA base image with nginx
# ──────────────────────────────────────────────
FROM ${BUILD_FROM}

# Install nginx and jq (jq already in base image, but ensure it's present)
RUN \
    apk add --no-cache \
        nginx \
        jq

# Create app directory
WORKDIR /app

# Copy built static files from the builder stage
COPY --from=builder /build/webapp /app/webapp

# Copy pre-baked config.json into the webapp directory (overrides default)
COPY config.json /app/webapp/config.json

# Copy nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy startup script
COPY run.sh /
RUN chmod a+x /run.sh

LABEL \
    io.hass.version="2026.08.04" \
    io.hass.type="app" \
    io.hass.arch="amd64,aarch64"

CMD [ "/run.sh" ]