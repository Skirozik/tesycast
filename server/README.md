# CarCast relay (Milestone 1)

Multi-tenant iPhone → Tesla screen-mirror relay. The iPhone broadcast extension
pushes JPEG frames over WebSocket; the Tesla browser pulls them as MJPEG. **No
hotspot** — the phone uploads over its own cellular/WiFi, the Tesla pulls over the
car's own connection.

```
iPhone ── wss://<DOMAIN>/ingest/<code>?secret=<publishSecret> ──► relay ──► Tesla
                                                                    │
                                          https://<DOMAIN>/watch/<code>  (MJPEG)
```

## Endpoints

| Method | Path                       | Purpose                                    |
|--------|----------------------------|--------------------------------------------|
| GET    | `/`                        | Branding landing page                      |
| GET    | `/watch/<code>`            | Tesla player (live screen mirror)          |
| GET    | `/status/<code>`           | `{publisher, viewers}` — viewer-presence   |
| WS     | `/ingest/<code>?secret=`   | Publisher (phone) — one per code           |
| WS     | `/view/<code>`             | Viewer (Tesla) — many per code             |
| GET    | `/player/<code>`           | Uploaded-video player                      |
| POST   | `/upload-video/<code>`     | Upload a video for `/player/<code>`        |

`<code>` = the 12-char key the iOS app generates (`[A-Za-z0-9]{6,64}`). Each code
is an isolated room: one publisher, many viewers. Rooms are in-memory and
garbage-collected when empty.

## Auth (M1)

Ingest requires `?secret=<publishSecret>`. Trust-on-first-use: the first publisher
for a code claims its secret; later ingests must match. Viewers need only the
code. **M2 replaces this with DB-backed pre-registration** (see the plan).

## SET YOUR VALUES HERE

1. **`docker-compose.yml`** (or a `.env` beside it): `BRAND`, `PUBLIC_DOMAIN`.
2. **`Caddyfile`**: replace `example.com` with your domain and `you@example.com`
   with your email (Let's Encrypt).
3. **iOS — `TeslaStream2/Config.swift`**: set `domain` to the same value as
   `PUBLIC_DOMAIN`.

## Run

Local (no TLS):

```bash
npm install
BRAND=CarCast PUBLIC_DOMAIN=localhost npm start   # http://localhost:3000
```

Production (Docker + auto-TLS via Caddy):

```bash
# after pointing DNS at this host and editing Caddyfile + compose env
docker compose up -d --build
```

Caddy provisions and renews TLS automatically and proxies `https://<domain>` →
`relay:3000` with WebSocket upgrades passing through.
