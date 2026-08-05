# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to date-based versioning (`YYYY.MM.DD`).

## [2026.08.06] - 2026-08-06

### Changed
- Switch to multi-arch manifest image (`ghcr.io/simpleace15/matrix-web-addon`) — HA Supervisor pulls a single manifest instead of per-arch images
- Build workflow now uses official HA `actions/helpers/info` to read version from `config.yaml` — version is the single source of truth, no manual label updates needed
- Builder injects `io.hass.version` label automatically — removed hardcoded version from Dockerfile
- Build workflow matches the official `home-assistant/apps-example` pattern

### Removed
- Removed `version-check.yml` workflow — redundant now that the build reads version directly from `config.yaml`

## [2026.08.05] - 2026-08-05

### Fixed
- nginx `map` directive crash on Alpine — removed `map` block, caching handled by `location` blocks instead
- Image name format corrected to match HA builder's arch-prefix naming (`{arch}-matrix-web-addon`)
- Build workflow now tags images with the addon version (not just `latest`) — HA Supervisor pulls `<image>:<version>`

### Changed
- Replaced all hardcoded domain references with `matrix.example.com` placeholder — real domain set at runtime via HA addon options

## [2026.08.04] - 2026-08-04

### Added
- Initial Element Web HA addon — builds Element Web v1.12.24 from source
- Two-stage Dockerfile: Node 24 + pnpm builder → HA base image with nginx runtime
- HA Ingress support (port 8080, SPA routing, iframe-compatible headers)
- Pre-baked `config.json` locked to configurable homeserver
- `run.sh` patches `config.json` at startup from `/data/options.json`
- GitHub Actions CI: 68-test validation suite (config, Dockerfile, run.sh)
- GitHub Actions build: multi-arch (amd64 + aarch64) image build + GHCR push
- Comprehensive README with architecture diagram and troubleshooting