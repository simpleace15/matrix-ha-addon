<div align="center">

# 💬 Matrix Web Chat

### Self-hosted Element Web Matrix chat client for Home Assistant

[![Version](https://img.shields.io/badge/version-2026.08.04-blue?style=flat-square)](https://github.com/simpleace15/matrix-ha-addon)
[![HA Add-on](https://img.shields.io/badge/Home%20Assistant-Add--on-41bdf5?style=flat-square)](https://www.home-assistant.io/)
[![Stage](https://img.shields.io/badge/stage-experimental-orange?style=flat-square)](https://developers.home-assistant.io/docs/add-ons/)
[![License](https://img.shields.io/badge/license-MIT-green?style=flat-square)](LICENSE)

[Features](#-features) · [Quick Start](#-quick-start) · [Configuration](#-configuration) · [Architecture](#-architecture) · [Troubleshooting](#-troubleshooting)

</div>

---

> **Element Web** is the flagship Matrix web client by [Element](https://element.io). This add-on builds it from source and serves it through Home Assistant Ingress — giving you a full Matrix chat UI in your HA sidebar, no separate app needed.

## ✨ Features

- **Full Matrix chat in HA** — Element Web built from source, served via HA Ingress
- **Sidebar integration** — appears as "Matrix Chat" in your HA sidebar, one click to open
- **Mobile via HA Companion app** — chat on your phone through the Home Assistant app, no separate Element install
- **Thread support** — first-class threads (MSC3440) enabled by default, the key reason we chose Element Web
- **End-to-end encryption** — full E2EE via Olm (WebAssembly), works entirely in the browser under HA's HTTPS
- **Multi-user** — each person logs in with their own Matrix account; sessions are isolated per browser/device
- **Pre-configured** — locked to our homeserver (`matrix.dogzilla.cloud`) out of the box, zero config needed
- **Dark theme by default** — matches HA's dark mode aesthetic
- **Configurable** — homeserver URL, server name, and brand can be overridden via HA add-on options

---

## 🚀 Quick Start

### Prerequisites

1. **Home Assistant** with add-on support (HA OS, Supervised, or Container + addon manager)
2. A **Matrix account** on a homeserver (e.g. `matrix.dogzilla.cloud`)

### Install the Add-on

1. In HA: **Settings** → **Add-ons** → **Add-on Store** → **⋮** → **Repositories**
2. Add: `https://github.com/simpleace15/matrix-ha-addon`
3. Find **Matrix Web Chat** → click **Install**
4. Click **Start**

That's it. The add-on appears in your HA sidebar as **Matrix Chat** 💬

### Log In

1. Click **Matrix Chat** in your HA sidebar
2. The Element Web login screen appears, pre-configured to `matrix.dogzilla.cloud`
3. Enter your Matrix username and password
4. You're in — your rooms, threads, and DMs are all there

> **Multi-user:** Each person who opens the HA Matrix Chat panel logs in with their own Matrix account. Tyler and Rachel each use their own Matrix credentials. Sessions persist per browser/device via localStorage — no shared session state.

---

## ⚙️ Configuration

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `homeserver_url` | no | `https://matrix.dogzilla.cloud` | URL of your Matrix homeserver |
| `homeserver_name` | no | `matrix.dogzilla.cloud` | Display name of the homeserver |
| `server_name` | no | `matrix.dogzilla.cloud` | Matrix server name (used for room directory) |
| `brand` | no | `Matrix Chat` | Branding shown in the Element UI |
| `allow_custom_homeservers` | no | `false` | Allow users to enter a custom homeserver at login |
| `log_level` | no | `info` | `debug` / `info` / `warning` / `error` / `critical` |

### Example: Point at a different homeserver

```yaml
homeserver_url: https://matrix.example.com
homeserver_name: matrix.example.com
server_name: matrix.example.com
brand: My Chat
```

---

## 🏗️ Architecture

```
┌──────────────────────────────────────────────────────┐
│  Home Assistant                                      │
│                                                      │
│  ┌────────────────────────────────────────────────┐  │
│  │  HA Add-on (Docker container)                  │  │
│  │                                                │  │
│  │  ┌──────────┐       ┌─────────────────────┐    │  │
│  │  │  nginx   │──────▶│  Element Web         │    │  │
│  │  │  :8080   │       │  (static SPA)        │    │  │
│  │  └──────────┘       └─────────────────────┘    │  │
│  │       ▲                                        │  │
│  │       │ HA Ingress (iframe, path-prefixed)      │  │
│  └───────┼────────────────────────────────────────┘  │
│          │                                           │
│    ┌─────┴──────┐  ┌──────────┐  ┌──────────┐        │
│    │ HA Sidebar │  │ HA Web   │  │ HA Companion│       │
│    │ "Matrix    │  │ Browser  │  │ App (mobile)│       │
│    │  Chat"     │  │          │  │            │       │
│    └────────────┘  └──────────┘  └──────────┘        │
└──────────────────────────────────────────────────────┘
                     │
                     │ HTTPS (Matrix Client-Server API)
                     ▼
┌──────────────────────────────────────────────────────┐
│  Matrix Homeserver (Synapse)                         │
│  https://matrix.dogzilla.cloud                       │
│                                                      │
│  Rooms · DMs · Threads · E2EE · Federation            │
└──────────────────────────────────────────────────────┘
```

**How it works:**

1. **Build stage** — Element Web is cloned from the official repo at a pinned release tag (`v1.12.24`) and built with `npm install && npm run build`, producing static files in `webapp/`
2. **Runtime stage** — The built static files are served by nginx inside the HA base Docker image (`ghcr.io/home-assistant/base:3.24`)
3. **HA Ingress** — The add-on uses Ingress (no exposed ports), so it's accessible from the HA sidebar and HA Companion app with full HA authentication
4. **Config patching** — At startup, `run.sh` reads `/data/options.json` and patches `config.json` with your configured homeserver URL, server name, and brand using `jq`
5. **E2EE** — All encryption (Olm/WASM) happens client-side in the browser. Works under HA's HTTPS with no special server-side config
6. **Thread support** — Enabled via `feature_threads: true` and `ThreadingView: true` in `config.json`

### Build details

| Component | Technology |
|-----------|-----------|
| Frontend | Element Web (React SPA, built from source) |
| Web server | nginx (static file serving, SPA routing) |
| Runtime | HA Add-on Docker container (`ghcr.io/home-assistant/base:3.24`) |
| Build | Node 20 (Debian Bookworm), `npm install && npm run build` |
| Protocol | Matrix Client-Server API (HTTPS to homeserver) |
| E2EE | Olm / WebAssembly (bundled in Element Web build) |

---

## 🔧 Troubleshooting

<details>
<summary><b>Blank page or loading forever in HA Ingress</b></summary>

- Hard refresh: Ctrl+Shift+R (or Cmd+Shift+R on Mac)
- Check the add-on logs: **Settings** → **Add-ons** → **Matrix Web Chat** → **Logs**
- The first build takes 5-10 minutes — if the add-on shows "starting" for a while, it's still building
- Element Web is a large SPA — on slow hardware, initial load can take 10-20 seconds

</details>

<details>
<summary><b>E2EE / encryption not working</b></summary>

- E2EE requires HTTPS — HA must be served over HTTPS (via Nabu Casa, Let's Encrypt, or reverse proxy)
- Element Web handles E2EE entirely in the browser via Olm (WebAssembly) — no server-side config needed
- If you see "Olm not installed" errors, the build may have failed to include Olm — rebuild the add-on
- On first login from a new device, you may need to verify your session with another device or recovery key

</details>

<details>
<summary><b>Can't connect to homeserver</b></summary>

- Verify the homeserver URL is correct in the add-on configuration
- Test connectivity: `curl https://matrix.dogzilla.cloud/_matrix/client/versions`
- If using a custom homeserver, update `homeserver_url`, `homeserver_name`, and `server_name` in the add-on config
- Check if the homeserver is behind a firewall that blocks requests from your HA instance

</details>

<details>
<summary><b>Threads not showing</b></summary>

- Threads are enabled by default in `config.json` (`feature_threads: true`, `ThreadingView: true`)
- Ensure you're on the latest add-on version
- Check Element settings → Labs → ensure threads are enabled
- Threads require the homeserver to support MSC3440 (Synapse 1.52+)

</details>

<details>
<summary><b>Build fails or takes too long</b></summary>

- The Element Web build needs ~2GB RAM and takes 5-10 minutes on typical HA hardware
- If the build OOMs, increase Docker's memory limit in HA settings
- The build is cached after the first successful run — subsequent restarts are fast
- Check the build logs for specific npm errors

</details>

---

## 👥 Multi-User

Each person who opens the HA Matrix Chat panel logs in with their own Matrix account:

- **Tyler** and **Rachel** each log in with their own Matrix credentials
- Sessions persist per browser/device via `localStorage` — no shared session state
- On mobile through the HA Companion app, each person's phone has its own session
- No logout needed when switching — just close and reopen (session persists)
- To switch accounts: log out from Element's settings, then log in with different credentials

---

## 📦 What's in the Build

```
matrix-ha-addon/
├── repository.yaml          # HA addon repo manifest
├── matrix_web_addon/         # The actual addon
│   ├── config.yaml          # HA addon config (slug, ingress, options schema)
│   ├── Dockerfile           # Two-stage: Node builder + HA base with nginx
│   ├── run.sh               # Startup: patch config.json, start nginx
│   ├── nginx.conf           # SPA routing, gzip, cache, Ingress-compatible
│   ├── config.json          # Element Web config (pre-baked, patched at runtime)
│   ├── README.md            # This file
│   └── LICENSE              # MIT
```

---

## 🔢 Versioning

This add-on uses **date-based versioning** (`YYYY.MM.DD`) to match the HA ecosystem convention.

| Component | Version |
|-----------|---------|
| Add-on | `2026.08.04` |
| Element Web | `v1.12.24` (pinned in Dockerfile) |

To update Element Web, change the `ELEMENT_WEB_VERSION` ARG in the Dockerfile to a new release tag and rebuild.

---

## License

MIT — see [LICENSE](LICENSE)

Element Web itself is licensed under the AGPLv3. This add-on builds and serves it unmodified; the add-on's own code (Dockerfile, nginx config, run script) is MIT licensed.
