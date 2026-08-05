# Global ARGs must be declared before any FROM to be available
# in FROM directives. HA Supervisor passes BUILD_FROM, BUILD_ARCH, BUILD_VERSION.
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24
ARG ELEMENT_WEB_VERSION=v1.12.24

# ──────────────────────────────────────────────
# Stage 1: Build Element Web from source
# ──────────────────────────────────────────────
FROM node:20-bookworm AS builder

# Redeclare ARG inside this stage so it's available in ADD/RUN
# (Docker scopes ARGs per-stage — global ARGs only work in FROM lines)
ARG ELEMENT_WEB_VERSION

# Download source tarball via Docker's ADD (uses BuildKit's HTTP client
# with host networking, not container DNS — avoids "Could not resolve host")
ADD https://github.com/element-hq/element-web/archive/refs/tags/${ELEMENT_WEB_VERSION}.tar.gz /tmp/element-web.tar.gz

# Extract the tarball
RUN mkdir -p /build && \
    tar xzf /tmp/element-web.tar.gz -C /build && \
    mv /build/element-web-* /build/element-web && \
    rm /tmp/element-web.tar.gz

WORKDIR /build/element-web

# Install dependencies and build
# Element uses npm; the build produces static files in webapp/
RUN npm install --legacy-peer-deps
RUN npm run build

# ──────────────────────────────────────────────
# Stage 2: Runtime — HA base image with nginx
# ──────────────────────────────────────────────
FROM ${BUILD_FROM}

# Install nginx and jq
RUN \
    apk add --no-cache \
        nginx \
        jq

# Create app directory
WORKDIR /app

# Copy built static files from the builder stage
COPY --from=builder /build/element-web/webapp /app/webapp

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