// Room Durable Object — one instance per stream code (env.ROOMS.idFromName(code)).
//
// Replaces the in-memory `rooms` Map of server/server.js:
//   publisher/viewers/videoViewers  -> hibernatable WebSockets, tagged
//                                      "publisher" / "viewer" / "video-viewer"
//   room.secret / room.mode         -> DO storage keys "secret" / "mode"
//   room.videoBuffer / videoType    -> storage "videoMeta" {size,type,chunks}
//                                      + "video:<i>" 1 MiB chunks (SQLite
//                                      values are capped at 2 MB each)
//
// Uses the WebSocket Hibernation API, so a room with idle sockets costs
// nothing between messages.
//
// The Workers runtime caps an inbound WebSocket message at 1 MiB, where the
// Node relay's `ws` default was 100 MiB. MJPEG publishers must keep each JPEG
// frame under 1 MiB or the /ingest socket is closed with 1009.

import { DurableObject } from 'cloudflare:workers';

const CHUNK = 1024 * 1024;             // 1 MiB per stored chunk
const MAX_VIDEO = 64 * 1024 * 1024;    // 64 MB cap (original allowed 512 MB in RAM)
const READ_BATCH = 8;                  // chunks fetched per storage.get() while streaming
const TAG_PUBLISHER = 'publisher';
const TAG_VIEWER = 'viewer';
const TAG_VIDEO_VIEWER = 'video-viewer';

// The Node relay's secret lived in process memory: a restart, or the last
// socket closing, released the code for re-claiming. Durable storage needs an
// explicit expiry, or a code could never be re-claimed after a reinstall.
// Publisher activity refreshes it; releasing it on socket close instead would
// let any anonymous /view connect-then-disconnect free the code mid-stream.
const CLAIM_TTL = 24 * 60 * 60 * 1000;

// Socket liveness sweep, standing in for the Node relay's 30s ping/terminate
// heartbeat. Viewers keep themselves fresh with an auto-responded "ping"
// (see mirrorHTML), which never wakes this object.
const SWEEP = 60 * 1000;
const STALE_AFTER = 150 * 1000;

const MEDIA_TYPE_RE = /^(video|audio)\/[a-z0-9.+-]+$/;

const json = obj => new Response(JSON.stringify(obj), {
  headers: { 'Content-Type': 'application/json' },
});
const text = (body, status = 200) => new Response(body, {
  status, headers: { 'Content-Type': 'text/plain' },
});

// Accept a WebSocket only to close it with an app close code (mirrors the
// Node server's ws.close(4xxx) on a just-established connection).
function closeWith(code, reason) {
  const pair = new WebSocketPair();
  const [client, server] = [pair[0], pair[1]];
  server.accept();
  server.close(code, reason);
  return new Response(null, { status: 101, webSocket: client });
}

// Compare secrets without leaking their contents through timing.
function secretsMatch(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string') return false;
  const enc = new TextEncoder();
  const ab = enc.encode(a), bb = enc.encode(b);
  let diff = ab.byteLength ^ bb.byteLength;
  const n = Math.max(ab.byteLength, bb.byteLength);
  for (let i = 0; i < n; i++) diff |= (ab[i] | 0) ^ (bb[i] | 0);
  return diff === 0;
}

// Only ever serve back a media type we recognise. The upload body is
// attacker-controlled, so echoing its Content-Type verbatim (as server.js did)
// would let "Content-Type: text/html" run script on the tesycast.com origin.
function safeMediaType(raw) {
  const type = (raw || '').split(';')[0].trim().toLowerCase();
  return MEDIA_TYPE_RE.test(type) ? type : 'video/mp4';
}

// RFC 7233 single byte-range: "bytes=<start>-<end>", "bytes=<start>-", or the
// suffix form "bytes=-<n>" (final n bytes). server.js mishandled the suffix and
// out-of-range forms (NaN / negative Content-Length); null here means 416.
function parseRange(header, total) {
  const m = /^bytes=(\d*)-(\d*)$/.exec(String(header).trim());
  if (!m) return null;
  const [, rawStart, rawEnd] = m;
  if (rawStart === '' && rawEnd === '') return null;

  if (rawStart === '') {
    const n = parseInt(rawEnd, 10);
    if (!Number.isFinite(n) || n <= 0) return null;
    return { start: Math.max(0, total - n), end: total - 1 };
  }
  const start = parseInt(rawStart, 10);
  if (!Number.isFinite(start) || start >= total) return null;
  let end = rawEnd === '' ? total - 1 : parseInt(rawEnd, 10);
  if (!Number.isFinite(end)) return null;
  if (end > total - 1) end = total - 1;
  if (end < start) return null;
  return { start, end };
}

export class Room extends DurableObject {
  // ws -> last activity (ms). In-memory only; rebuilt lazily after a wake,
  // so a hibernated room never pays a storage write per frame.
  #seen = new Map();

  constructor(ctx, env) {
    super(ctx, env);
    // Client-driven keepalive handled by the runtime: it refreshes the socket's
    // auto-response timestamp without waking this object.
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair('ping', 'pong'));
  }

  async fetch(request) {
    const url = new URL(request.url);
    const path = url.pathname;
    const upgrade = (request.headers.get('Upgrade') || '').toLowerCase();

    if (upgrade === 'websocket') {
      if (path.startsWith('/ingest/')) return this.#ingest(url);
      if (path.startsWith('/view/')) return this.#acceptTagged(TAG_VIEWER);
      if (path.startsWith('/video-events/')) return this.#acceptTagged(TAG_VIDEO_VIEWER);
      return closeWith(4004, 'unknown path');
    }

    // Internal (Worker -> DO) routes.
    if (path === '/internal/state') {
      const mode = await this.ctx.storage.get('mode');
      return json({ mode: mode || 'webrtc' });
    }
    if (path === '/internal/claim') {
      // Trust-on-first-use secret check for /token?role=publish.
      const ok = await this.#claim(url.searchParams.get('secret') || '');
      return ok ? text('ok') : text('bad secret', 403);
    }

    // Public per-room routes, forwarded verbatim by the Worker.
    if (path.startsWith('/mode/')) return this.#setMode(url);
    if (path.startsWith('/status/')) return this.#status();
    if (path.startsWith('/upload-video/')) return this.#uploadVideo(request, url);
    if (path.startsWith('/video/')) return this.#serveVideo(request);

    return text('Not found', 404);
  }

  // ── Claim (trust-on-first-use secret) ──────────────────────────────────────
  // The first non-empty secret presented for this code claims it; the claim is
  // refreshed by publisher activity and released only once CLAIM_TTL has passed
  // with no activity and no live publisher.
  async #claim(secret) {
    if (!secret) return false;              // an empty secret can never claim a code
    const stored = await this.ctx.storage.get('secret');
    const claimedAt = await this.ctx.storage.get('claimedAt');

    const unclaimed = stored === undefined;
    const lapsed = !unclaimed
      && (claimedAt === undefined || Date.now() - claimedAt > CLAIM_TTL)
      && this.ctx.getWebSockets(TAG_PUBLISHER).length === 0;

    if (unclaimed || lapsed) {
      await this.ctx.storage.put({ secret, claimedAt: Date.now() });
      await this.#scheduleSweep();
      return true;
    }
    if (!secretsMatch(stored, secret)) return false;
    await this.ctx.storage.put('claimedAt', Date.now());
    await this.#scheduleSweep();
    return true;
  }

  // POST /mode/<code>?mode=webrtc|mjpeg&secret=...
  async #setMode(url) {
    const secret = url.searchParams.get('secret') || '';
    const mode = url.searchParams.get('mode') === 'mjpeg' ? 'mjpeg' : 'webrtc';
    if (!(await this.#claim(secret))) return text('bad secret', 403);
    await this.ctx.storage.put('mode', mode);
    return json({ mode });
  }

  // GET /status/<code> — publisher presence + MJPEG viewer count only
  // (matches server.js, which counted room.viewers, not videoViewers).
  #status() {
    return json({
      publisher: this.ctx.getWebSockets(TAG_PUBLISHER).length > 0,
      viewers: this.ctx.getWebSockets(TAG_VIEWER).length,
    });
  }

  // ── WebSockets ─────────────────────────────────────────────────────────────
  // WS /ingest/<code>?secret=...
  async #ingest(url) {
    const secret = url.searchParams.get('secret') || '';
    if (!secret) return closeWith(4001, 'secret required');
    if (!(await this.#claim(secret))) return closeWith(4003, 'bad secret');

    const previous = this.ctx.getWebSockets(TAG_PUBLISHER);
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server, [TAG_PUBLISHER]);
    this.#touch(server);
    for (const old of previous) { try { old.close(4000, 'replaced'); } catch (_) {} }
    await this.#scheduleSweep();
    return new Response(null, { status: 101, webSocket: client });
  }

  async #acceptTagged(tag) {
    const pair = new WebSocketPair();
    const [client, server] = [pair[0], pair[1]];
    this.ctx.acceptWebSocket(server, [tag]);
    this.#touch(server);
    await this.#scheduleSweep();
    return new Response(null, { status: 101, webSocket: client });
  }

  // Publisher frames fan out to all MJPEG viewers.
  webSocketMessage(ws, message) {
    this.#touch(ws);
    const tags = this.ctx.getTags(ws);
    if (tags.includes(TAG_PUBLISHER)) {
      for (const viewer of this.ctx.getWebSockets(TAG_VIEWER)) {
        try { viewer.send(message); } catch (_) {}
      }
    }
  }

  async webSocketClose(ws, _code, _reason, _wasClean) {
    this.#seen.delete(ws);
    await this.#maybeCleanup(ws);
  }

  webSocketError(ws, _error) {
    this.#seen.delete(ws);
    try { ws.close(); } catch (_) {}
  }

  #touch(ws) { this.#seen.set(ws, Date.now()); }

  // Last sign of life: a frame we handled, or the runtime's auto-response to a
  // client "ping". 0 means we have not observed this socket yet (fresh wake).
  #lastActivity(ws) {
    let autoMs = 0;
    try {
      const auto = this.ctx.getWebSocketAutoResponseTimestamp(ws);
      if (auto) autoMs = auto.getTime();
    } catch (_) { /* socket not auto-responding */ }
    return Math.max(autoMs, this.#seen.get(ws) || 0);
  }

  // ── Alarm: liveness sweep + claim expiry ───────────────────────────────────
  async alarm() {
    const now = Date.now();
    for (const ws of this.ctx.getWebSockets()) {
      const last = this.#lastActivity(ws);
      if (!last) { this.#touch(ws); continue; }   // first sweep after a wake: grace period
      if (now - last > STALE_AFTER) {
        this.#seen.delete(ws);
        try { ws.close(1001, 'stale'); } catch (_) {}
      }
    }
    await this.#expireClaim();
    await this.#maybeCleanup(null);
    await this.#scheduleSweep();
  }

  async #expireClaim() {
    const claimedAt = await this.ctx.storage.get('claimedAt');
    if (claimedAt === undefined) return;
    if (Date.now() - claimedAt <= CLAIM_TTL) return;
    if (this.ctx.getWebSockets(TAG_PUBLISHER).length > 0) return;
    await this.ctx.storage.delete(['secret', 'claimedAt']);
  }

  // Sweep while sockets are open; otherwise just wake once at claim expiry.
  async #scheduleSweep() {
    const hasSockets = this.ctx.getWebSockets().length > 0;
    const claimedAt = await this.ctx.storage.get('claimedAt');
    let at = null;
    if (hasSockets) at = Date.now() + SWEEP;
    else if (claimedAt !== undefined) at = claimedAt + CLAIM_TTL + 1000;
    if (at === null) return;
    const existing = await this.ctx.storage.getAlarm();
    if (existing === null || existing > at) await this.ctx.storage.setAlarm(at);
  }

  // Mirror of server.js maybeCleanup(): once nothing references the room, drop
  // the transport mode. The claim is NOT dropped here — it expires on its own
  // TTL, so a passing viewer cannot release the code out from under a publisher.
  async #maybeCleanup(closing) {
    const live = tag => this.ctx.getWebSockets(tag).filter(w => w !== closing).length;
    if (live(TAG_PUBLISHER) > 0 || live(TAG_VIEWER) > 0 || live(TAG_VIDEO_VIEWER) > 0) return;
    const meta = await this.ctx.storage.get('videoMeta');
    if (meta) return; // a stored video keeps the room alive, like room.videoBuffer did
    await this.ctx.storage.delete('mode');
  }

  // ── Uploaded video ─────────────────────────────────────────────────────────
  // POST /upload-video/<code>?secret=... — store the body as 1 MiB chunks, then
  // notify all /video-events sockets with "new-video".
  //
  // server.js left this route unauthenticated; the room secret is required here
  // so a guessed code cannot plant content served from the tesycast.com origin.
  async #uploadVideo(request, url) {
    const secret = url.searchParams.get('secret') || '';
    if (!(await this.#claim(secret))) return text('bad secret', 403);

    const type = safeMediaType(request.headers.get('content-type'));

    // Buffer the body (capped), aborting with 413 as soon as the cap is hit,
    // so a failed upload never clobbers a previously stored video.
    const pieces = [];
    let size = 0;
    if (request.body) {
      for await (const piece of request.body) {
        size += piece.byteLength;
        if (size > MAX_VIDEO) return new Response(null, { status: 413 });
        pieces.push(piece);
      }
    }
    if (size === 0) return text('empty upload', 400);

    const oldMeta = await this.ctx.storage.get('videoMeta');

    // Re-slice the streamed pieces into fixed 1 MiB storage chunks.
    let idx = 0, fill = 0;
    let pending = new Uint8Array(Math.min(CHUNK, size));
    let batch = {};
    let batchKeys = 0;
    const flushBatch = async () => {
      if (batchKeys > 0) { await this.ctx.storage.put(batch); batch = {}; batchKeys = 0; }
    };
    const pushChunk = async bytes => {
      batch['video:' + idx] = bytes;
      idx++; batchKeys++;
      if (batchKeys >= 16) await flushBatch();
    };
    for (let p of pieces) {
      let view = p instanceof Uint8Array ? p : new Uint8Array(p);
      while (view.byteLength > 0) {
        const take = Math.min(view.byteLength, pending.byteLength - fill);
        pending.set(view.subarray(0, take), fill);
        fill += take;
        view = view.subarray(take);
        if (fill === pending.byteLength && pending.byteLength > 0) {
          await pushChunk(pending);
          const remaining = size - idx * CHUNK;
          pending = new Uint8Array(Math.max(0, Math.min(CHUNK, remaining)));
          fill = 0;
        }
      }
    }
    if (fill > 0) await pushChunk(pending.subarray(0, fill));
    await flushBatch();

    await this.ctx.storage.put('videoMeta', { size, type, chunks: idx });

    // Drop stale chunks from a previous, larger video.
    if (oldMeta && oldMeta.chunks > idx) {
      const stale = [];
      for (let i = idx; i < oldMeta.chunks; i++) stale.push('video:' + i);
      while (stale.length) await this.ctx.storage.delete(stale.splice(0, 128));
    }

    for (const ws of this.ctx.getWebSockets(TAG_VIDEO_VIEWER)) {
      try { ws.send('new-video'); } catch (_) {}
    }
    return text('OK');
  }

  // Stream [start, end] out of the stored chunks a few MiB at a time, so a
  // 64 MB video never materialises in the 128 MB isolate.
  #streamRange(start, end) {
    const storage = this.ctx.storage;
    let next = Math.floor(start / CHUNK);
    const last = Math.floor(end / CHUNK);
    const queue = [];
    return new ReadableStream({
      async pull(controller) {
        while (queue.length === 0) {
          if (next > last) { controller.close(); return; }
          const keys = [];
          const top = Math.min(last, next + READ_BATCH - 1);
          for (let i = next; i <= top; i++) keys.push('video:' + i);
          const got = await storage.get(keys);
          for (let i = next; i <= top; i++) {
            const chunk = got.get('video:' + i);
            if (!chunk) continue;
            const view = chunk instanceof Uint8Array ? chunk : new Uint8Array(chunk);
            const chunkStart = i * CHUNK;
            const from = Math.max(0, start - chunkStart);
            const to = Math.min(view.byteLength, end - chunkStart + 1);
            if (to > from) queue.push(view.slice(from, to));
          }
          next = top + 1;
        }
        controller.enqueue(queue.shift());
      },
    });
  }

  // GET|HEAD /video/<code> — byte-range video, like server.js.
  async #serveVideo(request) {
    const meta = await this.ctx.storage.get('videoMeta');
    if (!meta || meta.size === 0) return text('No video', 404);
    const total = meta.size;
    const base = {
      'Content-Type': meta.type,
      'Accept-Ranges': 'bytes',
      'X-Content-Type-Options': 'nosniff',
      'Content-Disposition': 'inline',
    };

    if (request.method === 'HEAD') {
      return new Response(null, {
        status: 200,
        headers: { ...base, 'Content-Length': String(total) },
      });
    }

    const range = request.headers.get('range');
    if (range) {
      const parsed = parseRange(range, total);
      if (!parsed) {
        return new Response(null, {
          status: 416,
          headers: { ...base, 'Content-Range': `bytes */${total}` },
        });
      }
      const { start, end } = parsed;
      return new Response(this.#streamRange(start, end), {
        status: 206,
        headers: {
          ...base,
          'Content-Range': `bytes ${start}-${end}/${total}`,
          'Content-Length': String(end - start + 1),
        },
      });
    }

    return new Response(this.#streamRange(0, total - 1), {
      status: 200,
      headers: { ...base, 'Content-Length': String(total) },
    });
  }
}
