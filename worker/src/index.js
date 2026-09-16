// Tesycast relay — Cloudflare Worker port of server/server.js.
//
// Stateless routes (hub, healthz, watch/player HTML, token minting) are
// handled here; everything per-room (secrets, mode, MJPEG relay sockets,
// uploaded video) lives in the Room Durable Object, addressed by
// env.ROOMS.idFromName(<code>).
//
// The iOS app calls GET /token/<code>?role=publish&secret=... and connects to
// the wsUrl in the response — env.LIVEKIT_WS_URL points it at LiveKit Cloud.

import { AccessToken } from 'livekit-server-sdk';
import { hubHTML, mirrorHTML, liveKitHTML, playerHTML } from './html.js';

export { Room } from './room.js';

// A valid room code: the 12-char key the iOS app generates. Kept permissive
// but bounded to prevent path abuse.
const CODE_RE = /^[A-Za-z0-9]{6,64}$/;

// Match "/prefix/<code>" -> code, else null.
function matchCode(pathname, prefix) {
  if (!pathname.startsWith(prefix + '/')) return null;
  const code = pathname.slice(prefix.length + 1);
  return CODE_RE.test(code) ? code : null;
}

const html = body => new Response(body, { headers: { 'Content-Type': 'text/html' } });
const text = (body, status = 200) => new Response(body, {
  status, headers: { 'Content-Type': 'text/plain' },
});
const json = obj => new Response(JSON.stringify(obj), {
  headers: { 'Content-Type': 'application/json' },
});

function roomStub(env, code) {
  return env.ROOMS.get(env.ROOMS.idFromName(code));
}

async function mintToken(env, code, role, identity) {
  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity, ttl: '6h',
  });
  at.addGrant({
    roomJoin: true,
    room: code,
    canPublish: role === 'publish',
    canSubscribe: role === 'subscribe',
    canPublishData: false,
  });
  return await at.toJwt();
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const pathname = url.pathname;

    // ── WebSockets: /ingest/<code>, /view/<code>, /video-events/<code> ──────
    if ((request.headers.get('Upgrade') || '').toLowerCase() === 'websocket') {
      for (const prefix of ['/ingest', '/view', '/video-events']) {
        const code = matchCode(pathname, prefix);
        if (code) return roomStub(env, code).fetch(request);
      }
      // Unknown WS path -> accept and close 4004, like server.js.
      const pair = new WebSocketPair();
      pair[1].accept();
      pair[1].close(4004, 'unknown path');
      return new Response(null, { status: 101, webSocket: pair[0] });
    }

    // ── POST routes ─────────────────────────────────────────────────────────
    if (request.method === 'POST') {
      // POST /mode/<code>?mode=webrtc|mjpeg&secret=... and
      // POST /upload-video/<code> — both stateful, handled inside the DO.
      const mcode = matchCode(pathname, '/mode');
      if (mcode) return roomStub(env, mcode).fetch(request);
      const ucode = matchCode(pathname, '/upload-video');
      if (ucode) return roomStub(env, ucode).fetch(request);
      return new Response(null, { status: 404 });
    }

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response(null, { status: 405 });
    }

    // GET /
    if (pathname === '/') return html(hubHTML(env.BRAND, env.PUBLIC_DOMAIN, env.REPO_URL));
    if (pathname === '/healthz') return text('ok');

    // GET /watch/<code> — the MJPEG canvas player unless ?mode=webrtc or the
    // room's stored mode is webrtc.
    let code = matchCode(pathname, '/watch');
    if (code) {
      let mode = url.searchParams.get('mode');
      if (!mode) {
        // Ask the room DO for its stored mode; a room that was never claimed
        // answers "mjpeg" (the only transport the app publishes) without
        // persisting anything.
        try {
          const res = await roomStub(env, code).fetch('https://do/internal/state');
          mode = (await res.json()).mode;
        } catch (_) {
          mode = 'mjpeg';
        }
      }
      return html(mode === 'mjpeg' ? mirrorHTML(env.BRAND, code) : liveKitHTML(env.BRAND, code));
    }

    // GET /token/<code>?role=publish|subscribe&secret=...
    code = matchCode(pathname, '/token');
    if (code) {
      const role = url.searchParams.get('role') === 'publish' ? 'publish' : 'subscribe';
      if (role === 'publish') {
        const secret = url.searchParams.get('secret') || '';
        if (!secret) return text('secret required', 400);
        // Trust-on-first-use check lives in the DO.
        const res = await roomStub(env, code).fetch(
          'https://do/internal/claim?secret=' + encodeURIComponent(secret),
          { method: 'POST' },
        );
        if (res.status !== 200) return text('bad secret', 403);
      }
      // A token with an empty wsUrl fails silently on both ends (the player
      // falls back to MJPEG, the app's publish connect just errors), so say so.
      if (!env.LIVEKIT_WS_URL) return text('LIVEKIT_WS_URL is not configured', 503);
      try {
        const identity = (role === 'publish' ? 'pub-' : 'sub-') + code + '-' + Date.now().toString(36);
        const token = await mintToken(env, code, role, identity);
        return json({ wsUrl: env.LIVEKIT_WS_URL, token });
      } catch (e) {
        console.error('[token] error:', e && e.message);
        return text('token error', 500);
      }
    }

    // GET /player/<code>
    code = matchCode(pathname, '/player');
    if (code) return html(playerHTML(env.BRAND, code));

    // GET /status/<code>
    code = matchCode(pathname, '/status');
    if (code) return roomStub(env, code).fetch(request);

    // GET|HEAD /video/<code>
    code = matchCode(pathname, '/video');
    if (code) return roomStub(env, code).fetch(request);

    return text('Not found', 404);
  },
};
