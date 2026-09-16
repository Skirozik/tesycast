# Tesycast Worker

Cloudflare Worker port of the Node relay (`../server/server.js`). Replaces the
Hetzner VPS stack (self-hosted LiveKit SFU + Node relay + Caddy):

- **LiveKit Cloud** replaces the self-hosted SFU — this Worker mints tokens
  pointing at it, so the iOS app and the `/watch` player repoint automatically
  via the `wsUrl` field of `GET /token/<code>`.
- **This Worker** replaces the Node relay + Caddy (Cloudflare terminates TLS,
  custom domains `tesycast.com` / `www.tesycast.com` are bound in
  `wrangler.jsonc`).
- **A `Room` Durable Object per stream code** (SQLite-backed, free plan)
  replaces the in-memory `rooms` Map: trust-on-first-use secret, mode
  (webrtc/mjpeg), MJPEG ingest/view WebSockets (hibernation API), and the
  uploaded video (stored as 1 MiB SQLite chunks).

All routes from `server.js` are preserved: `/`, `/healthz`, `/watch/<code>`,
`/token/<code>`, `/mode/<code>`, `/status/<code>`, `/player/<code>`,
`/video/<code>` (byte ranges), `/upload-video/<code>`, and WebSockets
`/ingest/<code>`, `/view/<code>`, `/video-events/<code>`.

**The shipping app uses the JPEG path**: the broadcast extension pushes frames to
`/ingest`, the Durable Object fans them out to `/view`, and `/watch` serves the
canvas player. The extension keeps every frame under 900 KB (the runtime closes a
socket on any message over 1 MiB) and sends a text `ping` every 25 s, which the
object auto-answers without waking or forwarding to viewers, so a static phone
screen does not get its socket reaped. The LiveKit/WebRTC routes remain live and
working but nothing in the app publishes to them.

## Deploy

```bash
cd worker
npm install

# Secrets (never in wrangler.jsonc):
npx wrangler secret put LIVEKIT_API_KEY      # from LiveKit Cloud project settings
npx wrangler secret put LIVEKIT_API_SECRET

npx wrangler deploy
```

`LIVEKIT_WS_URL` lives in `wrangler.jsonc` vars (it is public — every viewer
gets it in the `/token` response). Keep it there rather than passing
`--var` at deploy time: vars in the config file overwrite the deployed values
on every `wrangler deploy`, so a flag-only value silently reverts to empty and
breaks WebRTC on the next plain deploy.

For local development, put the same two secrets in `worker/.dev.vars`
(gitignored) and run `npx wrangler dev`.

### Tests

`test/e2e.mjs` exercises every route, the WebSocket relay (close codes, fan-out,
backpressure, publisher-gone), the trust-on-first-use claim, and byte-range video
serving. It needs Node 22+ and a running target:

```bash
npx wrangler dev            # in one terminal
node test/e2e.mjs           # against it (default http://127.0.0.1:8787)
BASE=https://tesycast.com node test/e2e.mjs   # against the live deployment
```

### Custom domains

`wrangler deploy` attaches the custom domains — but it refuses a hostname that
already has a normal DNS record (error 100117). The apex `tesycast.com` carried
an `A` record from the old VPS; that record has to be deleted in the Cloudflare
dashboard (DNS → Records) before the apex can be attached. `www` had no
conflicting record and attached on the first try.

## Behaviour changes vs. `server/server.js`

Mostly forced by the platform; the security ones are deliberate hardening of
flaws the original shared.

| Area | Old | New | Why |
|------|-----|-----|-----|
| Video upload size | 512 MB in RAM | 64 MB, 1 MiB SQLite chunks | a Worker/DO isolate has 128 MB |
| `/video` response | whole buffer in memory | streamed chunk by chunk | a 64 MB buffer plus its read batch would approach the isolate limit |
| Range requests | naive parse (`NaN` / negative `Content-Length` on odd input) | RFC 7233 parse, suffix `bytes=-N` supported, `416` when unsatisfiable | the old behaviour produced malformed responses |
| MJPEG frame size | up to 100 MB (`ws` default) | **1 MiB hard cap** (Workers limit; larger frames close the socket with 1009) | runtime limit — publishers must stay under it |
| Secret lifetime | in process memory; lost on restart or when the last socket closed | durable, refreshed by publisher activity, released after 24 h idle | storage is durable; releasing it on socket close let **any anonymous viewer** free a code mid-stream and re-claim it (stream hijack) |
| Empty secret | could claim a code | rejected (`403` / close `4003`) | an empty secret pre-claiming a code was a denial of service against the real publisher |
| Secret comparison | `===` | constant-time | avoids leaking the secret through timing |
| `/upload-video` | unauthenticated | requires the room secret | a guessed code could otherwise plant content served from the tesycast.com origin |
| Uploaded `Content-Type` | echoed back verbatim | coerced to a `video/*` or `audio/*` type, `X-Content-Type-Options: nosniff` | `Content-Type: text/html` was stored XSS on the apex origin |
| Zero-byte upload | stored, served as an empty 200 | rejected with `400` | a 0-byte video is never useful and broke the player |
| Socket keepalive | 30 s server ping, `terminate()` on no pong | client `ping` auto-answered by the runtime + a 60 s sweep that closes sockets idle > 150 s | hibernated DOs cannot run a timer; the auto-response never wakes the object |
| MJPEG fan-out | every frame sent to every viewer, unbounded | each viewer has a 4-frame window, refilled by a text `ack` from the player every 4 drawn frames; a viewer out of credit is handed only the freshest frame once it acks (refilled anyway after 5 s without an ack) | a Workers `send()` never blocks and has no buffered-amount signal, so a car draining slower than the phone uploads would queue frames in the object's 128 MB until eviction |
| Publisher leaves | viewers not told | viewers receive the text `publisher-gone`; the player drops its LIVE badge | otherwise the car sits on a frozen frame marked LIVE |
| Default `/watch` player | LiveKit (falls back to MJPEG after 8 s) | MJPEG canvas player; `?mode=webrtc` or a stored `webrtc` mode selects LiveKit | the app publishes only MJPEG; `/ingest` also records `mode=mjpeg` on every publisher connect |
| Room cleanup | whole room (incl. mode) forgotten when the last socket closed | mode kept; only in-memory frame state released | dropping the mode sent the next fresh `/watch` load through the LiveKit page's 8 s detour |
| `/token` with no LiveKit URL | n/a | `503` | minting a token with an empty `wsUrl` failed silently on both ends |

## Mapping to the old `server/`

| Old (VPS)                        | New (Cloudflare)                          |
|----------------------------------|-------------------------------------------|
| Caddy (TLS, proxy)               | Cloudflare edge / custom domains           |
| `livekit-server` container       | LiveKit Cloud (`LIVEKIT_WS_URL`)           |
| `server.js` HTTP routes          | `src/index.js` + `src/room.js`             |
| in-memory `rooms` Map            | `Room` Durable Object per code             |
| `deploy/.env`                    | `wrangler.jsonc` vars + Worker secrets     |

The old `server/` and `deploy/` directories are kept for reference and for
anyone who wants to self-host the original stack again.
