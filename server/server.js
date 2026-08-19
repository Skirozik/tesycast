'use strict';

// ───────────────────────────────────────────────────────────────────────────
// Tesycast relay — multi-tenant iPhone→Tesla screen mirror.
//
// The iPhone broadcast extension pushes JPEG frames over WebSocket to
//   wss://<DOMAIN>/ingest/<code>?secret=<publishSecret>
// The Tesla browser opens
//   https://<DOMAIN>/watch/<code>
// and receives those frames (MJPEG-over-WebSocket, rendered to a canvas).
//
// Each <code> is an isolated room: one publisher, many viewers. Node runs plain
// HTTP on 127.0.0.1:PORT behind Caddy, which terminates TLS and proxies wss.
// ───────────────────────────────────────────────────────────────────────────

const http      = require('http');
const WebSocket = require('ws');

// ─── Config (override via env; see server/Caddyfile + docker-compose.yml) ───
const PORT   = parseInt(process.env.PORT || '3000', 10);
const HOST   = process.env.HOST || '127.0.0.1';          // bind loopback; Caddy fronts TLS
const BRAND  = process.env.BRAND || 'Tesycast';           // TODO: set your product name
const DOMAIN = process.env.PUBLIC_DOMAIN || 'example.com'; // TODO: set your real domain
const REPO   = process.env.REPO_URL || 'https://github.com/Skirozik/tesycast'; // source, linked from the hub page

// LiveKit (WebRTC, Milestone 2). Defaults match `livekit-server --dev` so this
// works locally out of the box; override in production (same key/secret as livekit.yaml).
const LK_WS_URL = process.env.LIVEKIT_WS_URL   || `wss://lk.${DOMAIN}`;
const LK_KEY    = process.env.LIVEKIT_API_KEY  || 'devkey';
const LK_SECRET = process.env.LIVEKIT_API_SECRET || 'secret';

// livekit-server-sdk is ESM-only in v2 — lazy dynamic-import so this CommonJS file
// still loads even before the dep is installed (token routes just 500 until it is).
let _lkSdk = null;
async function lkSdk() {
  if (!_lkSdk) _lkSdk = await import('livekit-server-sdk');
  return _lkSdk;
}
async function mintToken(code, role, identity) {
  const { AccessToken } = await lkSdk();
  const at = new AccessToken(LK_KEY, LK_SECRET, { identity, ttl: '6h' });
  at.addGrant({
    roomJoin: true,
    room: code,
    canPublish:     role === 'publish',
    canSubscribe:   role === 'subscribe',
    canPublishData: false,
  });
  return await at.toJwt(); // async in v2
}

// A valid room code: the 12-char key the iOS app generates. Kept permissive but
// bounded to prevent path abuse.
const CODE_RE = /^[A-Za-z0-9]{6,64}$/;

// ─── Room state (in-memory; streams are ephemeral) ──────────────────────────
// code -> { publisher: ws|null, secret: string|null, viewers: Set<ws>,
//           videoBuffer: Buffer|null, videoType: string, videoViewers: Set<ws> }
const rooms = new Map();

function getRoom(code) {
  let room = rooms.get(code);
  if (!room) {
    room = {
      publisher: null,
      secret: null,
      mode: 'webrtc',          // 'webrtc' (LiveKit) | 'mjpeg' (M1 fallback) — set by phone via POST /mode
      viewers: new Set(),
      videoBuffer: null,
      videoType: 'video/mp4',
      videoViewers: new Set(),
    };
    rooms.set(code, room);
  }
  return room;
}

// Drop a room once nothing references it, so the Map can't grow unbounded.
function maybeCleanup(code) {
  const room = rooms.get(code);
  if (!room) return;
  if (!room.publisher && room.viewers.size === 0 &&
      !room.videoBuffer && room.videoViewers.size === 0) {
    rooms.delete(code);
  }
}

// ─── HTML ───────────────────────────────────────────────────────────────────
const esc = s => String(s).replace(/[&<>"']/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const hubHTML = `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(BRAND)}</title>
<style>
  *,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
  body{background:#04040a;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#fff;display:flex;flex-direction:column;align-items:center;justify-content:center;text-align:center;padding:24px}
  .ring{width:72px;height:72px;border-radius:50%;background:rgba(255,255,255,.06);border:1px solid rgba(255,255,255,.14);display:flex;align-items:center;justify-content:center;margin-bottom:24px;box-shadow:0 0 40px rgba(99,102,241,.2)}
  h1{font-size:clamp(34px,6vw,52px);font-weight:800;letter-spacing:-1.5px;background:linear-gradient(135deg,#fff 30%,rgba(255,255,255,.55));-webkit-background-clip:text;-webkit-text-fill-color:transparent;background-clip:text;margin-bottom:14px}
  p{font-size:16px;color:rgba(255,255,255,.45);max-width:440px;line-height:1.6}
  .foot{margin-top:36px;font-size:12px;color:rgba(255,255,255,.2);letter-spacing:.05em}
  .gh{position:fixed;top:18px;right:20px;display:flex;align-items:center;gap:7px;padding:8px 13px;border-radius:999px;background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.12);color:rgba(255,255,255,.62);font-size:13px;font-weight:500;text-decoration:none;transition:background .15s,color .15s,border-color .15s}
  .gh:hover,.gh:focus-visible{background:rgba(255,255,255,.1);border-color:rgba(255,255,255,.24);color:#fff}
  .gh svg{flex:none}
  @media (max-width:480px){.gh{top:12px;right:12px;padding:8px}.gh span{display:none}}
</style></head><body>
  <a class="gh" href="${esc(REPO)}" target="_blank" rel="noopener noreferrer" aria-label="View the source code on GitHub">
    <svg width="16" height="16" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.42 7.42 0 0 1 2-.27c.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8Z"/>
    </svg><span>GitHub</span>
  </a>
  <div class="ring">
    <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
      <path d="M5 12.55a11 11 0 0 1 14.08 0"/><path d="M1.42 9a16 16 0 0 1 21.16 0"/>
      <path d="M8.53 16.11a6 6 0 0 1 6.95 0"/><circle cx="12" cy="20" r="1" fill="currentColor" stroke="none"/></svg>
  </div>
  <h1>${esc(BRAND)}</h1>
  <p>Mirror your iPhone screen to your Tesla&rsquo;s browser &mdash; no hotspot required. Open the ${esc(BRAND)} app on your phone to get your personal watch link.</p>
  <div class="foot">${esc(DOMAIN)}</div>
</body></html>`;

function mirrorHTML(code) {
  const c = esc(code);
  return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(BRAND)} &mdash; Live</title>
<style>
  *,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
  body{background:#000;width:100vw;height:100vh;display:flex;align-items:center;justify-content:center;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
  canvas{max-width:100vw;max-height:100vh;display:block}
  #status{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);text-align:center;color:rgba(255,255,255,.5);font-size:15px;pointer-events:none}
  #status .icon{font-size:42px;margin-bottom:14px;opacity:.4}
  #badge{position:absolute;top:18px;right:18px;display:none;align-items:center;gap:6px;background:rgba(0,0,0,.5);border:1px solid rgba(239,68,68,.4);border-radius:20px;padding:6px 12px;font-size:12px;font-weight:700;color:#ef4444;letter-spacing:.08em}
  #badge .dot{width:7px;height:7px;background:#ef4444;border-radius:50%;box-shadow:0 0 6px #ef4444}
</style></head><body>
  <div id="badge"><div class="dot"></div>LIVE</div>
  <div id="status">
    <div class="icon">&#x1F4F1;</div>
    <div id="msg">Waiting for broadcast&hellip;</div>
    <div style="font-size:12px;margin-top:8px;color:rgba(255,255,255,.28)">Start Screen Mirror in the ${esc(BRAND)} app</div>
  </div>
  <canvas id="c"></canvas>
  <script>
    var code="${c}";
    var canvas=document.getElementById('c'),ctx=canvas.getContext('2d');
    var statusEl=document.getElementById('status'),badge=document.getElementById('badge'),msg=document.getElementById('msg');
    function connect(){
      var proto=location.protocol==='https:'?'wss:':'ws:';
      var ws=new WebSocket(proto+'//'+location.host+'/view/'+code);
      ws.binaryType='arraybuffer';
      ws.onmessage=function(e){
        statusEl.style.display='none';badge.style.display='flex';
        var blob=new Blob([e.data],{type:'image/jpeg'});
        var url=URL.createObjectURL(blob);var img=new Image();
        img.onload=function(){canvas.width=img.naturalWidth;canvas.height=img.naturalHeight;ctx.drawImage(img,0,0);URL.revokeObjectURL(url);};
        img.src=url;
      };
      ws.onclose=function(){
        msg.textContent='Reconnecting\\u2026';statusEl.style.display='block';badge.style.display='none';
        setTimeout(connect,1500);
      };
      ws.onerror=function(){try{ws.close();}catch(_){}};
    }
    connect();
  </script>
</body></html>`;
}

// LiveKit WebRTC player (Milestone 2). Fetches a subscribe token, connects to the
// SFU, attaches the remote screen track. Muted autoplay (Chromium blocks sound
// without a gesture) + tap-to-unmute. If no video track within 8s or connect
// fails, auto-falls back to the MJPEG player (?mode=mjpeg).
function liveKitHTML(code) {
  const c = esc(code);
  return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(BRAND)} &mdash; Live</title>
<style>
  *,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
  html,body{background:#000;width:100vw;height:100vh;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif}
  video{position:absolute;inset:0;width:100vw;height:100vh;object-fit:contain;background:#000}
  video.fill{object-fit:cover}
  #status{position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);text-align:center;color:rgba(255,255,255,.5);font-size:15px;pointer-events:none}
  #status .icon{font-size:42px;margin-bottom:14px;opacity:.4}
  #unmute{position:absolute;bottom:22px;left:50%;transform:translateX(-50%);display:none;background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.2);color:#fff;font-size:14px;font-weight:600;padding:10px 18px;border-radius:22px;cursor:pointer;backdrop-filter:blur(8px)}
  #fit{position:absolute;bottom:22px;right:22px;background:rgba(255,255,255,.12);border:1px solid rgba(255,255,255,.2);color:#fff;font-size:13px;font-weight:600;padding:8px 14px;border-radius:20px;cursor:pointer;backdrop-filter:blur(8px)}
</style></head><body>
  <video id="v" autoplay muted playsinline></video>
  <div id="status"><div class="icon">&#x1F4F1;</div><div id="msg">Connecting&hellip;</div></div>
  <div id="unmute">&#x1F50A; Tap for sound</div>
  <div id="fit">&#x2922; Fill</div>
  <script type="module">
    import { Room, RoomEvent, Track } from 'https://cdn.jsdelivr.net/npm/livekit-client@2/dist/livekit-client.esm.mjs';
    var code="${c}";
    var v=document.getElementById('v'),statusEl=document.getElementById('status'),msg=document.getElementById('msg'),unmute=document.getElementById('unmute'),fit=document.getElementById('fit');
    fit.onclick=function(){var on=v.classList.toggle('fill');fit.textContent=on?'\\u2922 Fit':'\\u2922 Fill';};
    var gotVideo=false;
    function fallback(){location.href='/watch/'+code+'?mode=mjpeg';}
    var fb=setTimeout(function(){if(!gotVideo)fallback();},8000);
    (async function(){
      var wsUrl,token;
      try{var r=await fetch('/token/'+code);var j=await r.json();wsUrl=j.wsUrl;token=j.token;}
      catch(e){clearTimeout(fb);fallback();return;}
      var room=new Room({adaptiveStream:false});
      room.on(RoomEvent.TrackSubscribed,function(track){
        track.attach(v);
        if(track.kind===Track.Kind.Video){gotVideo=true;clearTimeout(fb);statusEl.style.display='none';}
        if(track.kind===Track.Kind.Audio){unmute.style.display='block';}
      });
      room.on(RoomEvent.Disconnected,function(){statusEl.style.display='block';msg.textContent='Disconnected';});
      async function enableAudio(){try{await room.startAudio();}catch(_){}v.muted=false;unmute.style.display='none';}
      unmute.onclick=enableAudio;v.onclick=enableAudio;
      try{await room.connect(wsUrl,token);msg.textContent='Waiting for broadcast\\u2026';}
      catch(e){clearTimeout(fb);fallback();}
    })();
  </script>
</body></html>`;
}

function playerHTML(code) {
  const c = esc(code);
  return `<!DOCTYPE html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>${esc(BRAND)} &mdash; Video</title>
<style>
  *,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
  body{background:#000;width:100vw;height:100vh;display:flex;align-items:center;justify-content:center;overflow:hidden;font-family:-apple-system,BlinkMacSystemFont,sans-serif;color:#fff}
  video{max-width:100vw;max-height:100vh;display:none;outline:none}
  #status{text-align:center;color:rgba(255,255,255,.5);font-size:15px}
  #status .icon{font-size:42px;margin-bottom:14px;opacity:.4}
</style></head><body>
  <div id="status"><div class="icon">&#x25B6;&#xFE0F;</div><div>Waiting for video&hellip;</div>
    <div style="font-size:12px;margin-top:8px;color:rgba(255,255,255,.28)">Send a video from the ${esc(BRAND)} app</div></div>
  <video id="player" controls playsinline></video>
  <script>
    var code="${c}";
    var video=document.getElementById('player'),statusEl=document.getElementById('status'),loaded=false;
    function show(){statusEl.style.display='none';video.style.display='block';video.src='/video/'+code+'?t='+Date.now();video.play().catch(function(){});}
    function check(){if(loaded)return;fetch('/video/'+code,{method:'HEAD'}).then(function(r){if(r.ok){loaded=true;show();}}).catch(function(){});}
    var proto=location.protocol==='https:'?'wss:':'ws:';
    var ws=new WebSocket(proto+'//'+location.host+'/video-events/'+code);
    ws.onmessage=function(e){if(e.data==='new-video'){loaded=true;show();}};
    check();setInterval(check,2500);
  </script>
</body></html>`;
}

// ─── URL helpers ────────────────────────────────────────────────────────────
// Match "/prefix/<code>" -> code, else null.
function matchCode(pathname, prefix) {
  if (!pathname.startsWith(prefix + '/')) return null;
  const code = pathname.slice(prefix.length + 1);
  return CODE_RE.test(code) ? code : null;
}

// ─── HTTP server ────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const parsed   = new URL(req.url, 'http://localhost');
  const pathname = parsed.pathname;

  // POST /mode/<code>?mode=webrtc|mjpeg&secret=<publishSecret>
  // The phone declares which transport it will use, so /watch serves the right player.
  if (req.method === 'POST') {
    const mcode = matchCode(pathname, '/mode');
    if (mcode) {
      const secret = parsed.searchParams.get('secret') || '';
      const mode   = parsed.searchParams.get('mode') === 'mjpeg' ? 'mjpeg' : 'webrtc';
      const room   = getRoom(mcode);
      if (room.secret === null) room.secret = secret;        // trust-on-first-use
      else if (room.secret !== secret) { res.writeHead(403, { 'Content-Type': 'text/plain' }); res.end('bad secret'); return; }
      room.mode = mode;
      res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ mode: room.mode }));
      return;
    }
  }

  // POST /upload-video/<code>
  if (req.method === 'POST') {
    const code = matchCode(pathname, '/upload-video');
    if (code) {
      const chunks = [];
      let size = 0;
      const MAX = 512 * 1024 * 1024; // 512 MB guard
      req.on('data', chunk => {
        size += chunk.length;
        if (size > MAX) { res.writeHead(413); res.end(); req.destroy(); return; }
        chunks.push(chunk);
      });
      req.on('end', () => {
        const room = getRoom(code);
        room.videoBuffer = Buffer.concat(chunks);
        room.videoType   = req.headers['content-type'] || 'video/mp4';
        console.log('[+] video uploaded to', code, (room.videoBuffer.length / 1048576).toFixed(1), 'MB');
        room.videoViewers.forEach(ws => { if (ws.readyState === WebSocket.OPEN) ws.send('new-video'); });
        res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end('OK');
      });
      req.on('error', () => { res.writeHead(500); res.end(); });
      return;
    }
    res.writeHead(404); res.end(); return;
  }

  if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405); res.end(); return; }

  // GET /
  if (pathname === '/') { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(hubHTML); return; }
  if (pathname === '/healthz') { res.writeHead(200, { 'Content-Type': 'text/plain' }); res.end('ok'); return; }

  // GET /watch/<code>  (live screen mirror) — WebRTC by default, MJPEG fallback.
  // ?mode=mjpeg forces the M1 player (used by the LiveKit page's auto-fallback).
  let code = matchCode(pathname, '/watch');
  if (code) {
    const override = parsed.searchParams.get('mode');
    const room = rooms.get(code);
    const mode = override || (room && room.mode) || 'webrtc';
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(mode === 'mjpeg' ? mirrorHTML(code) : liveKitHTML(code));
    return;
  }

  // GET /token/<code>?role=publish&secret=...   (subscribe token if no role)
  code = matchCode(pathname, '/token');
  if (code) {
    const role = parsed.searchParams.get('role') === 'publish' ? 'publish' : 'subscribe';
    if (role === 'publish') {
      const secret = parsed.searchParams.get('secret') || '';
      const room = getRoom(code);
      if (!secret) { res.writeHead(400, { 'Content-Type': 'text/plain' }); res.end('secret required'); return; }
      if (room.secret === null) room.secret = secret;        // trust-on-first-use
      else if (room.secret !== secret) { res.writeHead(403, { 'Content-Type': 'text/plain' }); res.end('bad secret'); return; }
    }
    try {
      const identity = (role === 'publish' ? 'pub-' : 'sub-') + code + '-' + Date.now().toString(36);
      const token = await mintToken(code, role, identity);
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ wsUrl: LK_WS_URL, token }));
    } catch (e) {
      console.error('[token] error:', e.message);
      res.writeHead(500, { 'Content-Type': 'text/plain' }); res.end('token error (is livekit-server-sdk installed?)');
    }
    return;
  }

  // GET /player/<code>  (uploaded video)
  code = matchCode(pathname, '/player');
  if (code) { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(playerHTML(code)); return; }

  // GET /status/<code>  (viewer-presence signal for the app's multi-path logic)
  code = matchCode(pathname, '/status');
  if (code) {
    const room = rooms.get(code);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({
      publisher: !!(room && room.publisher),
      viewers:   room ? room.viewers.size : 0,
    }));
    return;
  }

  // GET|HEAD /video/<code>  (byte-range video)
  code = matchCode(pathname, '/video');
  if (code) {
    const room = rooms.get(code);
    if (!room || !room.videoBuffer) { res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('No video'); return; }
    const buf = room.videoBuffer, total = buf.length, range = req.headers.range;
    if (req.method === 'HEAD') {
      res.writeHead(200, { 'Content-Length': total, 'Content-Type': room.videoType, 'Accept-Ranges': 'bytes' }); res.end(); return;
    }
    if (range) {
      const [s, e] = range.replace(/bytes=/, '').split('-');
      const start = parseInt(s, 10), end = e ? parseInt(e, 10) : total - 1;
      res.writeHead(206, {
        'Content-Range': `bytes ${start}-${end}/${total}`, 'Accept-Ranges': 'bytes',
        'Content-Length': end - start + 1, 'Content-Type': room.videoType,
      });
      res.end(buf.slice(start, end + 1));
    } else {
      res.writeHead(200, { 'Content-Length': total, 'Content-Type': room.videoType, 'Accept-Ranges': 'bytes' });
      res.end(buf);
    }
    return;
  }

  res.writeHead(404, { 'Content-Type': 'text/plain' }); res.end('Not found');
});

// ─── WebSocket server ───────────────────────────────────────────────────────
const wss = new WebSocket.Server({ server });

wss.on('connection', (ws, req) => {
  const parsed   = new URL(req.url, 'http://localhost');
  const pathname = parsed.pathname;

  // Publisher: /ingest/<code>?secret=<publishSecret>
  let code = matchCode(pathname, '/ingest');
  if (code) {
    const secret = parsed.searchParams.get('secret') || '';
    if (!secret) { ws.close(4001, 'secret required'); return; }
    const room = getRoom(code);
    // Trust-on-first-use: the first publisher for a code claims its secret.
    // (M2 replaces this with DB-backed pre-registration — see plan.)
    if (room.secret === null) room.secret = secret;
    else if (room.secret !== secret) { ws.close(4003, 'bad secret'); return; }

    if (room.publisher && room.publisher !== ws) { try { room.publisher.close(4000, 'replaced'); } catch (_) {} }
    room.publisher = ws;
    console.log('[+] publisher connected:', code);

    ws.on('message', data => {
      room.viewers.forEach(v => { if (v.readyState === WebSocket.OPEN) v.send(data); });
    });
    ws.on('close', () => {
      if (room.publisher === ws) room.publisher = null;
      console.log('[-] publisher disconnected:', code);
      maybeCleanup(code);
    });
    ws.on('error', () => { try { ws.close(); } catch (_) {} });
    return;
  }

  // Viewer: /view/<code>
  code = matchCode(pathname, '/view');
  if (code) {
    const room = getRoom(code);
    room.viewers.add(ws);
    console.log('[+] viewer connected:', code, '(' + room.viewers.size + ')');
    ws.on('close', () => { room.viewers.delete(ws); maybeCleanup(code); });
    ws.on('error', () => { try { ws.close(); } catch (_) {} });
    return;
  }

  // Video-ready notifications: /video-events/<code>
  code = matchCode(pathname, '/video-events');
  if (code) {
    const room = getRoom(code);
    room.videoViewers.add(ws);
    ws.on('close', () => { room.videoViewers.delete(ws); maybeCleanup(code); });
    ws.on('error', () => { try { ws.close(); } catch (_) {} });
    return;
  }

  ws.close(4004, 'unknown path');
});

// Keepalive: drop dead sockets so rooms don't leak.
const heartbeat = setInterval(() => {
  wss.clients.forEach(ws => {
    if (ws.isAlive === false) return ws.terminate();
    ws.isAlive = false;
    try { ws.ping(); } catch (_) {}
  });
}, 30000);
wss.on('connection', ws => { ws.isAlive = true; ws.on('pong', () => { ws.isAlive = true; }); });
wss.on('close', () => clearInterval(heartbeat));

server.listen(PORT, HOST, () => {
  console.log(`${BRAND} relay listening on http://${HOST}:${PORT} (public: https://${DOMAIN})`);
});
