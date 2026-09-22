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
  uplink and adapts resolution/quality on the fly — sharper on WiFi, smoother and
  lower-latency on LTE, with no knobs to touch.
- **The car never falls behind.** If the car's connection or CPU is slower than the phone,
  it is always handed the *freshest* frame rather than a growing backlog.

---

## How it works

```
 iPhone                              tesycast.com  (Cloudflare Worker + Durable Object)   Tesla browser
 ┌──────────────────────┐           ┌──────────────────────────────────────┐            (own internet)
 │ ReplayKit broadcast  │  JPEG     │  /ingest/<code>  (publisher socket)  │  JPEG      /watch/<code>
 │ extension            ├──frames──►│  /view/<code>    (viewer fan-out)    ├──frames──►  <canvas>
 │ (JPEG encode +       │  over WS  │  /watch/<code>   (player page)       │  over WS    latest-frame
 │  adaptive quality)   │           │  /status/<code>  (LIVE badge)        │◄──acks───   draw loop
 └──────────────────────┘           └──────────────────────────────────────┘
        audio ───────────────────────── Bluetooth ─────────────────────────────►  car speakers
```

1. **Setup (once per install).** The app generates a random 12-character **stream code**
   (public — it's in the watch URL) and a random 24-character **publish secret** (private —
   it proves the right to publish and is never part of the watch URL; the app and the
   extension send it to the relay as a `?secret=` query parameter over TLS). Both are shared
   with the broadcast extension through the App Group.
2. **Phone: start a broadcast.** Opening the streaming screen tells the relay this code
   uses the image transport (`POST /mode`). Tapping the broadcast button starts the
   ReplayKit extension, which opens a WebSocket to `/ingest/<code>?secret=…`. It keeps
   **one frame in flight at a time**: a screen frame that arrives while the previous one is
   still uploading, or sooner than 1/30 s after it, is simply dropped (never queued). A frame
   that passes is JPEG-encoded at the current quality preset and sent. Audio frames are
   ignored — audio goes over Bluetooth.
3. **Adaptive quality.** The extension times how long each frame takes to clear the socket
   and keeps a moving average (80% old / 20% new). Six presets run from 420 px wide at JPEG
   quality 0.34 to 1200 px at 0.52, starting in the middle (660 px / 0.40). Two consecutive
   slow sends (average above ~38 ms, i.e. slower than 30 fps) step the ladder *down* one
   rung; twenty consecutive fast sends (below ~18 ms) step it *up* one rung — back off fast,
   probe slowly, the same asymmetry TCP uses, so it settles instead of oscillating. The
   average resets after every step. Separately, any encoded frame over 900 KB steps the
   ladder down and is re-encoded, repeating until it fits (a frame already at the lightest
   preset is skipped), because the Cloudflare Workers runtime hosting the relay closes a
   socket on any WebSocket message over 1 MiB.
4. **Relay: fan-out.** One Durable Object per stream code holds the publisher socket and
   every viewer socket. Each frame is forwarded to viewers that have credit: a viewer gets a
   **4-frame window** and refills it by sending `ack` after every 4 frames it draws. A viewer
   that is out of credit is skipped and, when it acks, receives only the **latest** frame.
   That bounds the relay's memory per viewer and keeps a slow car current instead of behind.
5. **Tesla: paint.** `/watch/<code>` serves a page that opens `/view/<code>` and draws each
   JPEG onto a full-screen canvas (`object-fit: contain`, so nothing is cropped). It decodes
   one frame at a time and, if frames arrive faster than the car's CPU can draw, keeps only
   the freshest one. A `LIVE` badge shows while frames flow.
6. **Status.** The app polls `/status/<code>` every 1.5 s and drives its LIVE/READY badge and
   timer from whether the relay currently holds a publisher socket for the code. When the
   phone stops, the relay tells viewers `publisher-gone` so the car returns to
   "Waiting for broadcast…" instead of freezing on the last frame marked LIVE.
7. **Keepalive.** ReplayKit only delivers frames when the screen changes, so both the
   extension and the player send a `ping` every 25 s; the relay answers `pong` without
   waking the room and reaps sockets silent for 150 s. Both ends reconnect automatically
   after a drop (the extension after 2 s, the player after 1.5 s).

Each phone gets its own code, so streams stay isolated between users, and the relay
remembers each code's transport between broadcasts so a fresh page load in the car always
gets the canvas player.

> **Latency note:** the phone and the Tesla both talk through the relay, so every frame makes
> a cloud round-trip even though the two devices sit in the same car. Cloudflare routes each
> side to its nearest edge and the room lives near whoever opened it first; that round-trip
> is the baseline delay.

---

## Security model

- The **stream code** is public but unguessable (12 alphanumeric characters, ~71 bits).
- The **publish secret** is required to publish or change the transport for a code. The
  first secret presented for a code **claims** it; a different secret is refused (`403`, or
  WebSocket close `4003`). The claim is released only **24 hours after the last authenticated
  publisher request** (a `/mode` post or an `/ingest` connect with the right secret; an open
  broadcast refreshes it every minute) and never while a publisher socket is open. It is
  deliberately *not* released when sockets close — otherwise anyone who knew a watch code
  could open and close an anonymous viewer socket to free the code and publish into someone
  else's room.
- Empty secrets can never claim a code. Secrets are compared in constant time.
- Viewers can only receive; anything a viewer sends other than `ack`/`ping` is ignored, so a
  viewer cannot inject frames.

---

## Limits worth knowing

| What | Limit | Where it comes from |
|------|-------|---------------------|
| Frame size | 1 MiB per WebSocket message; the extension stays under 900 KB | Cloudflare Workers runtime |
| Relay requests | ~100,000 per day on the free plan (frames count 20 per request, plus acks and status polls) | Cloudflare Durable Objects free tier — an all-day 30 fps session uses roughly 70–75k |
| Uploaded video (`/player`) | 64 MB per file | a Worker isolate has 128 MB of memory |
| Cost | $0 with hard caps; nothing on file that can bill | Cloudflare Workers free plan, LiveKit Cloud free tier |

---

## Repository layout

| Path | What it is |
|------|------------|
| [`TeslaStream2/`](TeslaStream2/) | iOS app (SwiftUI) — welcome, home, streaming UI, config, state |
| [`BroadcastExtension/`](BroadcastExtension/) | ReplayKit extension — JPEG-encodes the screen, adaptive quality, WebSocket push |
| [`worker/`](worker/) | **Live backend** — Cloudflare Worker + Durable Object: `/ingest`, `/view` fan-out with backpressure, `/watch` canvas player, `/status`, LiveKit tokens. Tests in `worker/test/e2e.mjs` |
| [`server/`](server/) | The original Node relay the Worker was ported from (reference) |
| [`deploy/`](deploy/) | The original self-hosted stack: relay + Caddy + LiveKit (reference) |
| [`XCODE_SETUP.md`](XCODE_SETUP.md) | One-time Xcode setup (targets, Info.plist keys, capabilities) |

> **Note on WebRTC:** the repo also contains a LiveKit/WebRTC path — `LiveKitPublisher.swift`
> in the app, the `?mode=webrtc` player in the relay, and a LiveKit Cloud project the Worker
> mints tokens for. It was the original design and it works on a laptop, but Tesla's browser
> won't play the video in the car, so the app ships the image path above as its **only**
> transport and nothing in the app publishes to LiveKit. The code is kept for reference and
> for non-Tesla viewers.

---

## Getting started

### 📱 iOS app
See **[XCODE_SETUP.md](XCODE_SETUP.md)**: open the project in Xcode, point
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
- **Backend:** [Cloudflare Workers](https://workers.cloudflare.com) + Durable Objects (WebSocket hibernation) · LiveKit Cloud (dormant WebRTC path)

---

## Status

Live at **[tesycast.com](https://tesycast.com)**, running entirely on free tiers. Early beta:
the image path is the working transport, audio is over Bluetooth, and quality adapts to your
connection. Best experienced parked.
