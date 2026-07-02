# Tesycast 🚗📱

**Mirror your iPhone screen to your Tesla's browser — no hotspot required.**

### 🌐 [tesycast.com](https://tesycast.com)

Tesycast streams your iPhone's screen to the Tesla's built-in web browser over the
internet. Your phone uploads over its **own** cellular/WiFi connection, and the Tesla
pulls the stream over **its own** connection — so you never have to turn on your
phone's Personal Hotspot.

> **Note:** the Tesla needs its own internet (Premium Connectivity LTE or WiFi). No
> software can deliver a stream to a car that has no network path — but with Tesycast,
> the phone's hotspot is no longer that path.

---

## How it works

```
 iPhone                          tesycast.com  (one VPS, Docker + Caddy TLS)          Tesla browser
 ┌───────────────────┐          ┌───────────────────────────────────────────┐       (own internet:
 │ ReplayKit         │  WebRTC  │  LiveKit SFU  (WebRTC, self-hosted)         │  WebRTC   LTE / WiFi)
 │ broadcast ext ────┼─────────►│  Node relay   (tokens · player · fallback) │◄────────► /watch/<code>
 │ (LiveKit publish) │  H.264   │                                            │          <video> player
 └───────────────────┘  +audio  └───────────────────────────────────────────┘
```

1. The **iPhone** captures its screen via a ReplayKit broadcast extension and publishes
   it to a self-hosted **LiveKit** (WebRTC) server as **H.264 video + app audio**.
2. The **Tesla** opens `https://tesycast.com/watch/<code>` and plays the low-latency
   WebRTC stream right in its browser.
3. A small **Node relay** mints access tokens, serves the player page, and keeps an
   MJPEG path as a fallback.

Each phone gets its own unguessable **stream code**, so streams stay isolated between users.

---

## Features

- 📺 **Low-latency WebRTC** — crisp up to 1440p H.264, sub-second delay
- 🔊 **Audio with A/V sync** — the mirrored app's sound, full-fidelity (real mic muted)
- 🚗 **No hotspot** — works over the Tesla's own connection
- 🔁 **Keeps streaming in the background** — use other apps while it mirrors
- 👥 **Multi-tenant** — private per-device stream codes
- 🖥️ **Fit / Fill toggle**, muted-autoplay with tap-to-unmute

---

## Repository layout

| Path | What it is |
|------|------------|
| [`TeslaStream2/`](TeslaStream2/) | iOS app (SwiftUI) — home, streaming UI, LiveKit publisher, config |
| [`BroadcastExtension/`](BroadcastExtension/) | ReplayKit broadcast upload extension (LiveKit screen publisher) |
| [`server/`](server/) | Node relay — LiveKit tokens, the `/watch` player, MJPEG fallback |
| [`deploy/`](deploy/) | Self-hosted stack: LiveKit + relay + Caddy (Docker Compose) |
| [`M2_SETUP.md`](M2_SETUP.md) | One-time Xcode setup (Swift package, Info.plist keys, capabilities) |

---

## Getting started

### 📱 iOS app
See **[M2_SETUP.md](M2_SETUP.md)**: add the LiveKit Swift package to both targets, set
the Info.plist keys + Background Modes → Audio, point
[`TeslaStream2/Config.swift`](TeslaStream2/Config.swift) at your domain, then build to a
real device (screen capture doesn't work in the simulator).

### ☁️ Server
See **[deploy/README.md](deploy/README.md)**: one VPS runs LiveKit + the relay + Caddy
(automatic TLS). Point DNS at it, set `deploy/.env`, and:
```bash
cd deploy && docker compose up -d --build
```

---

## Tech stack

- **iOS:** SwiftUI · ReplayKit · [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) (WebRTC)
- **Server:** Node.js · [LiveKit](https://livekit.io) (self-hosted SFU) · Caddy · Docker

---

## Status

Live and working at **[tesycast.com](https://tesycast.com)**. WebRTC is the primary
transport; an MJPEG relay remains as a compatibility fallback.
