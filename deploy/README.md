# CarCast deploy (Milestone 2 — LiveKit WebRTC)

Runs the whole stack on **one VPS**: LiveKit SFU + the Node relay + Caddy (auto-TLS).

## 1. DNS
Point these A-records at your VPS public IP:
- `<DOMAIN>` — landing page, `/watch` player, `/token`, `/mode`, M1 relay
- `lk.<DOMAIN>` — LiveKit signaling (wss)

## 2. Firewall (open these)
| Port | Proto | Why |
|------|-------|-----|
| 80, 443 | TCP | HTTPS + wss (Caddy / ACME) |
| 7881 | TCP | WebRTC TCP fallback |
| 3478 | UDP | embedded TURN |
| 50000-60000 | UDP | WebRTC media |

(7880 stays on localhost — Caddy fronts it.)

## 3. Configure + run
```bash
cd deploy
cp .env.example .env      # set PUBLIC_DOMAIN, ACME_EMAIL, and a long LIVEKIT_API_SECRET
docker compose up -d --build
```
Caddy auto-provisions TLS for `<DOMAIN>` and `lk.<DOMAIN>`. The relay reads the same
`LIVEKIT_API_KEY/SECRET` as LiveKit (single source in `.env`), so tokens verify.

## 4. Point the app at it
Set `domain` in [TeslaStream2/Config.swift](../TeslaStream2/Config.swift) to `<DOMAIN>`
(the app derives `wss://lk.<DOMAIN>` for signaling). Rebuild in Xcode.

## 5. Verify (matches the plan's A–F)
- **A** `docker compose ps` all up; `curl https://<DOMAIN>/healthz` → `ok`; `wss://lk.<DOMAIN>` reachable.
  Install the LiveKit CLI (`brew install livekit-cli`) and join a test room:
  `lk room join --url wss://lk.<DOMAIN> --api-key devkey --api-secret <secret> --identity t1 test`.
- **B** Tokens: `curl "https://<DOMAIN>/token/test?role=publish&secret=s1"` and `/token/test` (subscribe);
  decode the JWTs (jwt.io) and confirm the `video` grants.
- **C–F** see the plan (`~/.claude/plans/ok-look-at-all-jiggly-shamir.md`).

## If UDP is blocked on some viewer networks (TURN/TLS over 443)
The provided config does TURN over **UDP 3478**, which covers phone-cellular + Tesla-LTE.
For restrictive networks that block UDP entirely you need TURN-over-TLS on 443, which
requires Caddy's layer4 module. The simplest correct way is the official generator:
```bash
docker run --rm -it -v$PWD/generated:/output livekit/generate
```
Then copy its `caddy.yaml` + TURN settings and merge the `relay` service from this
compose into the generated `docker-compose.yaml`.
