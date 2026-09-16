# Tesycast 🚗📱

**Mirror your iPhone screen to your Tesla's browser — no hotspot required.**

### 🌐 [tesycast.com](https://tesycast.com)

Tesycast streams your iPhone's screen to the Tesla's built-in web browser over the
internet. Your phone uploads over its **own** cellular/WiFi connection and the Tesla pulls
the stream over **its own** connection — so you never turn on your phone's Personal Hotspot.
Park, open a video on your phone, and watch it on the car's screen.

> **You need:** a Tesla with its own internet (Premium Connectivity LTE or WiFi). No
> software can deliver a stream to a car with no network path — Tesycast just means that
> path no longer has to be your phone's hotspot.

---

## Why images, not video

Tesla's in-car browser **cripples video playback** — even a plain `.mp4` opened directly in
the browser plays one frame and then freezes. So Tesycast doesn't send "video" at all. It
sends the screen as a fast stream of **JPEG stills painted to a `<canvas>`**, which the
browser draws as ordinary images and never routes through its (blocked) video decoder.
That's the whole trick, and it's why it actually plays on the car.

- **Audio** rides **Bluetooth** from the phone to the car speakers (the image stream is
  video-only), so pair your phone as you would for music.
- **Quality self-tunes.** The broadcast extension times how fast each frame clears your
  uplink and adapts resolution/quality on the fly (AIMD) — sharper on WiFi, smoother and
  lower-latency on LTE, with no knobs to touch.

---

## How it works

```
 iPhone                              tesycast.com  (one VPS, Docker + Caddy TLS)      Tesla browser
 ┌──────────────────────┐           ┌──────────────────────────────────────┐         (own internet)
 │ ReplayKit broadcast  │  JPEG     │  Node relay                          │  JPEG   /watch/<code>
 │ extension            ├──frames──►│  /ingest/<code>  (publisher socket)  ├─frames─►  <canvas>
 │ (JPEG encode +       │  over WS  │  /view/<code>    (viewer fan-out)    │  over WS  latest-frame
 │  adaptive quality)   │           │  /watch/<code>   (player page)       │           draw loop
 └──────────────────────┘           └──────────────────────────────────────┘
        audio ───────────────────────── Bluetooth ─────────────────────────────►  car speakers
```

1. The **iPhone** captures its screen with a ReplayKit broadcast extension, JPEG-encodes
   each frame at an adaptive resolution, and pushes it over a WebSocket to the relay.
2. The **Node relay** fans each frame out to whoever is viewing that stream code.
3. The **Tesla** opens `https://tesycast.com/watch/<code>` and paints the frames onto a
   canvas, always jumping to the freshest frame so a slow-CPU car never falls behind.

Each phone gets its own unguessable **stream code**, so streams stay isolated between users.

> **Latency note:** the phone and the Tesla both talk through the relay (currently in
> Ashburn, VA), so every frame makes a cloud round-trip even though the two devices sit in
> the same car. That round-trip is the baseline delay; everything else is tuned around it.

---

## Repository layout

| Path | What it is |
|------|------------|
| [`TeslaStream2/`](TeslaStream2/) | iOS app (SwiftUI) — welcome, home, streaming UI, config, state |
| [`BroadcastExtension/`](BroadcastExtension/) | ReplayKit extension — JPEG-encodes the screen, adaptive quality, WebSocket push |
| [`server/`](server/) | Node relay — `/ingest` publisher, `/view` fan-out, `/watch` canvas player |
| [`deploy/`](deploy/) | Self-hosted stack: relay + Caddy (auto-TLS) + LiveKit, via Docker Compose |
| [`M2_SETUP.md`](M2_SETUP.md) | One-time Xcode setup (targets, Info.plist keys, capabilities) |

> **Note on WebRTC:** the repo also contains a LiveKit/WebRTC path (`LiveKitPublisher.swift`
> and the LiveKit SFU in `deploy/`). It was the original design but is **dormant** — Tesla's
> browser can't decode the video, so the app ships the image path above by default
> (`StreamManager.compatibilityMode`). The WebRTC code is kept for reference / non-Tesla targets.

---

## Getting started

### 📱 iOS app
See **[M2_SETUP.md](M2_SETUP.md)**: open the project in Xcode, point
[`TeslaStream2/Config.swift`](TeslaStream2/Config.swift) at your relay domain, and build to a
**real device** (screen capture doesn't work in the simulator). Distribute to testers via
TestFlight.

### ☁️ Server
See **[deploy/README.md](deploy/README.md)**: one VPS runs the relay + Caddy (automatic TLS).
Point DNS at it, set `deploy/.env`, and:
```bash
cd deploy && docker compose up -d --build
```

---

## Tech stack

- **iOS:** SwiftUI · ReplayKit · Core Image (JPEG encode) · URLSession WebSocket
- **Server:** Node.js (`ws`) · Caddy · Docker

---

## Status

Live at **[tesycast.com](https://tesycast.com)**. Early beta: the image path is the working
default, audio is over Bluetooth, and quality adapts to your connection. Best experienced parked.
