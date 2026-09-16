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

Tesla's in-car browser **will not play video while the car is in Drive** — even a plain
`.mp4` opened directly in the browser plays one frame and then freezes. So Tesycast doesn't
send "video" at all. It sends the screen as a fast stream of **JPEG stills painted to a
`<canvas>`**, which the browser draws as ordinary images and never routes through its
(blocked) video decoder. That's the whole trick, and it's why it actually plays on the car.

- **Audio** rides **Bluetooth** from the phone to the car speakers (the image stream is
  video-only), so pair your phone as you would for music.
- **Quality self-tunes.** The broadcast extension times how fast each frame clears your
  uplink and adapts resolution/quality on the fly (AIMD) — sharper on WiFi, smoother and
  lower-latency on LTE, with no knobs to touch. Frames are also capped under the relay's
  1 MiB message limit so one large frame can never drop the connection.

---

## How it works

```
 iPhone                              tesycast.com  (Cloudflare Worker + Durable Object)   Tesla browser
 ┌──────────────────────┐           ┌──────────────────────────────────────┐            (own internet)
 │ ReplayKit broadcast  │  JPEG     │  /ingest/<code>  (publisher socket)  │  JPEG      /watch/<code>
 │ extension            ├──frames──►│  /view/<code>    (viewer fan-out)    ├──frames──►  <canvas>
 │ (JPEG encode +       │  over WS  │  /watch/<code>   (player page)       │  over WS    latest-frame
 │  adaptive quality)   │           │  /status/<code>  (LIVE badge)        │             draw loop
 └──────────────────────┘           └──────────────────────────────────────┘
        audio ───────────────────────── Bluetooth ─────────────────────────────►  car speakers
```

1. The **iPhone** captures its screen with a ReplayKit broadcast extension, JPEG-encodes
   each frame at an adaptive resolution, and pushes it over a WebSocket to the relay.
2. The **relay** — a Cloudflare Worker with one Durable Object per stream code — fans each
   frame out to whoever is viewing that code. Nothing runs on a server you maintain.
3. The **Tesla** opens `https://tesycast.com/watch/<code>` and paints the frames onto a
   canvas, always jumping to the freshest frame so a slow-CPU car never falls behind.

Each phone gets its own unguessable **stream code**, so streams stay isolated between users.

> **Latency note:** the phone and the Tesla both talk through the relay, so every frame
> makes a cloud round-trip even though the two devices sit in the same car. Cloudflare
> routes each side to its nearest edge, and the room's Durable Object lives near whoever
> opened it first; that round-trip is the baseline delay.

---

## Repository layout

| Path | What it is |
|------|------------|
| [`TeslaStream2/`](TeslaStream2/) | iOS app (SwiftUI) — welcome, home, streaming UI, config, state |
| [`BroadcastExtension/`](BroadcastExtension/) | ReplayKit extension — JPEG-encodes the screen, adaptive quality, WebSocket push |
| [`worker/`](worker/) | **Live backend** — Cloudflare Worker + Durable Object: `/ingest`, `/view` fan-out, `/watch` canvas player, LiveKit tokens |
| [`server/`](server/) | The original Node relay the Worker was ported from (reference) |
| [`deploy/`](deploy/) | The original self-hosted stack: relay + Caddy + LiveKit (reference) |
| [`M2_SETUP.md`](M2_SETUP.md) | One-time Xcode setup (targets, Info.plist keys, capabilities) |

> **Note on WebRTC:** the repo also contains a LiveKit/WebRTC path (`LiveKitPublisher.swift`
> in the app, the LiveKit player in the relay, and a LiveKit Cloud project the Worker mints
> tokens for). It was the original design and it works on a laptop, but Tesla's browser
> won't play the video in the car, so the app ships the image path above as its only
> transport. The WebRTC code is kept for reference / non-Tesla viewers.

---

## Getting started

### 📱 iOS app
See **[M2_SETUP.md](M2_SETUP.md)**: open the project in Xcode, point
[`TeslaStream2/Config.swift`](TeslaStream2/Config.swift) at your relay domain, and build to a
**real device** (screen capture doesn't work in the simulator). Distribute to testers via
TestFlight.

### ☁️ Backend
See **[worker/README.md](worker/README.md)**. The relay runs on **Cloudflare Workers** — no
VPS, no Docker:
```bash
cd worker && npm install
npx wrangler secret put LIVEKIT_API_KEY      # only needed for the dormant WebRTC path
npx wrangler secret put LIVEKIT_API_SECRET
npx wrangler deploy
```
To self-host the original stack instead, see **[deploy/README.md](deploy/README.md)**.

---

## Tech stack

- **iOS:** SwiftUI · ReplayKit · Core Image (JPEG encode) · URLSession WebSocket
- **Backend:** [Cloudflare Workers](https://workers.cloudflare.com) + Durable Objects (WebSocket hibernation)

---

## Status

Live at **[tesycast.com](https://tesycast.com)**, running entirely on free tiers. Early beta:
the image path is the working transport, audio is over Bluetooth, and quality adapts to your
connection. Best experienced parked.
