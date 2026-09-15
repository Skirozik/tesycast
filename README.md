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
 iPhone                    LiveKit Cloud (WebRTC SFU)                 Tesla browser
 ┌───────────────────┐    ┌────────────────────────────┐            (own internet:
 │ ReplayKit         │───►│  media in ──────► media out│───────────►  LTE / WiFi)
 │ broadcast ext     │    └────────────────────────────┘            /watch/<code>
 │ (LiveKit publish) │            ▲              ▲                   <video> player
 └─────────┬─────────┘            │ token        │ token
           │                ┌─────┴──────────────┴─────┐
           └───────────────►│  tesycast.com            │
             token / mode   │  Cloudflare Worker + DO  │
                            │  (tokens · pages · MJPEG)│
                            └──────────────────────────┘
```

1. The **iPhone** captures its screen via a ReplayKit broadcast extension and publishes
   it to **LiveKit Cloud** (WebRTC) as **H.264 video + app audio**.
2. The **Tesla** opens `https://tesycast.com/watch/<code>` and plays the low-latency
   WebRTC stream right in its browser.
3. A small **Cloudflare Worker** mints access tokens, serves the player page, and keeps
   an MJPEG path as a fallback. Nothing runs on a server you have to maintain.

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
| [`worker/`](worker/) | **Live backend** — Cloudflare Worker + Durable Object: LiveKit tokens, the `/watch` player, MJPEG fallback |
| [`server/`](server/) | The original Node relay this Worker was ported from (reference) |
| [`deploy/`](deploy/) | The original self-hosted stack: LiveKit + relay + Caddy (reference) |
| [`M2_SETUP.md`](M2_SETUP.md) | One-time Xcode setup (Swift package, Info.plist keys, capabilities) |

---

## Getting started

### 📱 iOS app
See **[M2_SETUP.md](M2_SETUP.md)**: add the LiveKit Swift package to both targets, set
the Info.plist keys + Background Modes → Audio, point
[`TeslaStream2/Config.swift`](TeslaStream2/Config.swift) at your domain, then build to a
real device (screen capture doesn't work in the simulator).

### ☁️ Backend
See **[worker/README.md](worker/README.md)**. Media runs on **LiveKit Cloud**; the site,
token API and MJPEG fallback run on a **Cloudflare Worker** — no VPS, no Docker:
```bash
cd worker && npm install
npx wrangler secret put LIVEKIT_API_KEY
npx wrangler secret put LIVEKIT_API_SECRET
npx wrangler deploy
```
To self-host the original stack instead, see **[deploy/README.md](deploy/README.md)**.

---

## Tech stack

- **iOS:** SwiftUI · ReplayKit · [LiveKit Swift SDK](https://github.com/livekit/client-sdk-swift) (WebRTC)
- **Backend:** [Cloudflare Workers](https://workers.cloudflare.com) + Durable Objects · [LiveKit Cloud](https://livekit.io) (SFU)

---

## Status

Live at **[tesycast.com](https://tesycast.com)**, running entirely on free tiers
(Cloudflare Workers + LiveKit Cloud) after the original VPS was retired. WebRTC is the
primary transport; an MJPEG relay remains as a compatibility fallback.
