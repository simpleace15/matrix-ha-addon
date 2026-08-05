# Global ARGs must be declared before any FROM to be available
# in FROM directives. HA Supervisor passes BUILD_FROM, BUILD_ARCH, BUILD_VERSION.
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.24
ARG ELEMENT_WEB_VERSION=v1.12.24

# ──────────────────────────────────────────────
# Stage 1: Build Element Web from source
# Element Web v1.12.24 is a pnpm monorepo requiring Node >=22.18 and pnpm 11.x
# ──────────────────────────────────────────────
FROM node:24-bookworm AS builder

# Install pnpm 11.x (Element Web pins pnpm 11.5.2)
RUN npm install -g pnpm@11.5.2

ARG ELEMENT_WEB_VERSION

# Download source tarball
ADD https://github.com/element-hq/element-web/archive/refs/tags/${ELEMENT_WEB_VERSION}.tar.gz /tmp/element-web.tar.gz

# Extract the tarball
RUN mkdir -p /build && \
    tar xzf /tmp/element-web.tar.gz -C /build && \
    mv /build/element-web-* /build/element-web && \
    rm /tmp/element-web.tar.gz

WORKDIR /build/element-web

# Install dependencies using pnpm (frozen lockfile ensures reproducible builds)
RUN pnpm install --frozen-lockfile

# Build Element Web — produces static files in apps/web/webapp/
RUN pnpm --dir apps/web build

# Copy default config into the built webapp directory
RUN cp apps/web/config.sample.json apps/web/webapp/config.json

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
COPY --from=builder /build/element-web/apps/web/webapp /app/webapp

# Copy pre-baked config.json into the webapp directory (overrides default)
COPY config.json /app/webapp/config.json

# Copy nginx config
COPY nginx.conf /etc/nginx/nginx.conf

# Copy startup script
COPY run.sh /
RUN chmod a+x /run.sh

LABEL \
    io.hass.version="2026.08.05" \
    io.hass.type="app" \
    io.hass.arch="amd64,aarch64"

CMD [ "/run.sh" ]