'use strict';

const http      = require('http');
const WebSocket = require('ws');

// ─── Uploaded video state ─────────────────────────────────────────────────
let videoBuffer      = null;
let videoContentType = 'video/mp4';

// ─── HUB PAGE  (tescast.com) ──────────────────────────────────────────────
const hubHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TesCast</title>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }

    body {
      background: #04040a;
      min-height: 100vh;
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, sans-serif;
      color: #fff;
      display: flex;
      flex-direction: column;
      align-items: center;
      overflow-x: hidden;
    }

    /* ── wavy canvas background ── */
    #wave-canvas {
      position: fixed;
      inset: 0;
      width: 100vw;
      height: 100vh;
      z-index: 0;
      pointer-events: none;
    }

    /* ── all content sits above canvas ── */
    .page {
      position: relative;
      z-index: 1;
      width: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
    }

    /* ── hero ── */
    .hero {
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 72px 24px 48px;
      text-align: center;
    }
    .logo-ring {
      width: 72px; height: 72px;
      border-radius: 50%;
      background: rgba(255,255,255,0.06);
      border: 1px solid rgba(255,255,255,0.14);
      display: flex; align-items: center; justify-content: center;
      font-size: 30px;
      margin-bottom: 24px;
      box-shadow: 0 0 40px rgba(99,102,241,0.2);
    }
    .hero h1 {
      font-size: clamp(36px, 6vw, 56px);
      font-weight: 800;
      letter-spacing: -1.5px;
      background: linear-gradient(135deg, #fff 30%, rgba(255,255,255,0.55));
      -webkit-background-clip: text;
      -webkit-text-fill-color: transparent;
      background-clip: text;
      line-height: 1.1;
      margin-bottom: 14px;
    }
    .hero p {
      font-size: 16px;
      color: rgba(255,255,255,0.42);
      max-width: 400px;
      line-height: 1.6;
    }

    /* ── cards grid ── */
    .cards {
      width: 100%;
      max-width: 900px;
      padding: 0 20px 60px;
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 16px;
    }

    .card {
      display: flex;
      flex-direction: column;
      align-items: flex-start;
      padding: 28px 24px 52px;
      background: rgba(255,255,255,0.05);
      backdrop-filter: blur(20px);
      -webkit-backdrop-filter: blur(20px);
      border: 1px solid rgba(255,255,255,0.1);
      border-radius: 24px;
      text-decoration: none;
      color: #fff;
      cursor: pointer;
      transition: background 0.2s, transform 0.2s, border-color 0.2s, box-shadow 0.2s;
      position: relative;
      overflow: hidden;
    }
    .card:hover, .card:active {
      background: rgba(255,255,255,0.09);
      border-color: rgba(255,255,255,0.2);
      transform: translateY(-3px);
      box-shadow: 0 20px 40px rgba(0,0,0,0.4);
    }

    /* colored glow on hover */
    .card.mirror:hover { box-shadow: 0 20px 40px rgba(59,130,246,0.15); }
    .card.video:hover  { box-shadow: 0 20px 40px rgba(168,85,247,0.15); }

    /* accent top border */
    .card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 1px;
      opacity: 0.8;
    }
    .card.mirror::before { background: linear-gradient(90deg, transparent, #3b82f6, #6366f1, transparent); }
    .card.video::before  { background: linear-gradient(90deg, transparent, #a855f7, #ec4899, transparent); }

    .card-icon {
      width: 54px; height: 54px;
      border-radius: 16px;
      display: flex; align-items: center; justify-content: center;
      font-size: 26px;
      margin-bottom: 20px;
      flex-shrink: 0;
    }
    .card.mirror .card-icon { background: rgba(59,130,246,0.14);  border: 1px solid rgba(59,130,246,0.25); }
    .card.video  .card-icon { background: rgba(168,85,247,0.14);  border: 1px solid rgba(168,85,247,0.25); }

    .card h2 {
      font-size: 18px;
      font-weight: 700;
      margin-bottom: 8px;
      letter-spacing: -0.2px;
    }
    .card p {
      font-size: 13px;
      color: rgba(255,255,255,0.4);
      line-height: 1.6;
    }

    .card-arrow {
      position: absolute;
      bottom: 22px; right: 22px;
      width: 30px; height: 30px;
      border-radius: 50%;
      background: rgba(255,255,255,0.07);
      border: 1px solid rgba(255,255,255,0.12);
      display: flex; align-items: center; justify-content: center;
      font-size: 14px;
      color: rgba(255,255,255,0.45);
      transition: background 0.2s, color 0.2s;
    }
    .card:hover .card-arrow {
      background: rgba(255,255,255,0.14);
      color: rgba(255,255,255,0.8);
    }

    /* ── footer ── */
    .footer {
      margin-top: auto;
      padding: 28px;
      font-size: 12px;
      color: rgba(255,255,255,0.15);
      letter-spacing: 0.05em;
    }
  </style>
</head>
<body>

  <!-- Wavy background canvas -->
  <canvas id="wave-canvas"></canvas>

  <div class="page">

    <!-- Hero -->
    <div class="hero">
      <div class="logo-ring">
        <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
          <path d="M5 12.55a11 11 0 0 1 14.08 0"/>
          <path d="M1.42 9a16 16 0 0 1 21.16 0"/>
          <path d="M8.53 16.11a6 6 0 0 1 6.95 0"/>
          <circle cx="12" cy="20" r="1" fill="currentColor" stroke="none"/>
        </svg>
      </div>
      <h1>TesCast</h1>
      <p>Your Tesla&rsquo;s browser, supercharged. Mirror and stream from your iPhone.</p>
    </div>

    <!-- Feature cards -->
    <div class="cards">

      <a class="card mirror" href="/mirror">
        <div class="card-icon">
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#3b82f6" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
            <rect x="5" y="2" width="14" height="20" rx="2" ry="2"/>
            <line x1="12" y1="18" x2="12.01" y2="18"/>
          </svg>
        </div>
        <h2>Screen Mirror</h2>
        <p>Broadcast your iPhone screen live to your Tesla browser in real time.</p>
        <div class="card-arrow">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
        </div>
      </a>

      <a class="card video" href="/player">
        <div class="card-icon">
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke="#a855f7" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round">
            <polygon points="5 3 19 12 5 21 5 3" fill="#a855f7" fill-opacity="0.2"/>
          </svg>
        </div>
        <h2>Stream Video</h2>
        <p>Send any video from the TesCast app and play it instantly on your Tesla.</p>
        <div class="card-arrow">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="9 18 15 12 9 6"/></svg>
        </div>
      </a>

    </div>

    <div class="footer">tescast.com</div>

  </div>

  <script type="module">
    import { createNoise3D } from 'https://unpkg.com/simplex-noise@4.0.1/dist/esm/simplex-noise.js';

    const canvas = document.getElementById('wave-canvas');
    const ctx    = canvas.getContext('2d');
    const noise  = createNoise3D();

    const COLORS = ['#3b82f6', '#6366f1', '#a855f7', '#ec4899', '#22d3ee'];
    const WAVE_COUNT  = 5;
    const WAVE_WIDTH  = 60;
    const BLUR        = 12;
    const OPACITY     = 0.45;
    const SPEED       = 0.0018;

    let w, h, nt = 0, rafId;

    function resize() {
      w = canvas.width  = window.innerWidth;
      h = canvas.height = window.innerHeight;
      ctx.filter = 'blur(' + BLUR + 'px)';
    }

    function drawWaves() {
      nt += SPEED;
      for (let i = 0; i < WAVE_COUNT; i++) {
        ctx.beginPath();
        ctx.lineWidth   = WAVE_WIDTH;
        ctx.strokeStyle = COLORS[i % COLORS.length];
        for (let x = 0; x < w; x += 4) {
          const y = noise(x / 900, 0.35 * i, nt) * 110;
          ctx.lineTo(x, y + h * 0.5);
        }
        ctx.stroke();
        ctx.closePath();
      }
    }

    function render() {
      ctx.fillStyle   = '#04040a';
      ctx.globalAlpha = OPACITY;
      ctx.fillRect(0, 0, w, h);
      drawWaves();
      rafId = requestAnimationFrame(render);
    }

    resize();
    window.addEventListener('resize', resize);
    render();
  </script>

</body>
</html>`;


// ─── MIRROR PAGE  (tescast.com/mirror) ───────────────────────────────────
const mirrorHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TesCast &mdash; Screen Mirror</title>
  <style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #000;
      width: 100vw; height: 100vh;
      display: flex; align-items: center; justify-content: center;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
    }
    canvas { max-width: 100vw; max-height: 100vh; display: block; }
    #status {
      position: absolute;
      top: 50%; left: 50%;
      transform: translate(-50%, -50%);
      text-align: center;
      color: rgba(255,255,255,0.5);
      font-size: 15px;
      pointer-events: none;
    }
    #status .icon { font-size: 42px; margin-bottom: 14px; opacity: 0.4; }
    #back {
      position: absolute;
      top: 18px; left: 18px;
      background: rgba(255,255,255,0.1);
      border: 1px solid rgba(255,255,255,0.15);
      border-radius: 10px;
      color: #fff;
      font-size: 13px;
      padding: 8px 14px;
      text-decoration: none;
      backdrop-filter: blur(8px);
      -webkit-backdrop-filter: blur(8px);
    }
    #live-badge {
      position: absolute;
      top: 18px; right: 18px;
      display: none;
      align-items: center;
      gap: 6px;
      background: rgba(0,0,0,0.5);
      border: 1px solid rgba(239,68,68,0.4);
      border-radius: 20px;
      padding: 6px 12px;
      font-size: 12px;
      font-weight: 700;
      color: #ef4444;
      letter-spacing: 0.08em;
      backdrop-filter: blur(8px);
    }
    #live-badge .dot {
      width: 7px; height: 7px;
      background: #ef4444;
      border-radius: 50%;
      box-shadow: 0 0 6px #ef4444;
    }
  </style>
</head>
<body>

  <a href="/" id="back">&lsaquo; TesCast</a>

  <div id="live-badge">
    <div class="dot"></div>
    LIVE
  </div>

  <div id="status">
    <div class="icon">&#x1F4F1;</div>
    <div>Waiting for broadcast&hellip;</div>
    <div style="font-size:12px;margin-top:8px;color:rgba(255,255,255,0.28)">Start Screen Mirror in the TesCast app</div>
  </div>

  <canvas id="c"></canvas>

  <script>
    const canvas = document.getElementById('c');
    const ctx    = canvas.getContext('2d');
    const status = document.getElementById('status');
    const badge  = document.getElementById('live-badge');

    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(proto + '//' + location.host + '/view');
    ws.binaryType = 'arraybuffer';

    ws.onmessage = function(e) {
      status.style.display = 'none';
      badge.style.display  = 'flex';
      const blob = new Blob([e.data], { type: 'image/jpeg' });
      const url  = URL.createObjectURL(blob);
      const img  = new Image();
      img.onload = function() {
        canvas.width  = img.naturalWidth;
        canvas.height = img.naturalHeight;
        ctx.drawImage(img, 0, 0);
        URL.revokeObjectURL(url);
      };
      img.src = url;
    };

    ws.onclose = function() {
      status.querySelector('div:last-child').textContent = 'Disconnected \u2014 refresh to reconnect';
      status.style.display = 'block';
      badge.style.display  = 'none';
    };
  </script>

</body>
</html>`;


// ─── PLAYER PAGE  (tescast.com/player) ───────────────────────────────────
const playerHTML = `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TesCast &mdash; Stream Video</title>
  <style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #000;
      width: 100vw; height: 100vh;
      display: flex; flex-direction: column;
      align-items: center; justify-content: center;
      overflow: hidden;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      color: #fff;
    }
    video {
      max-width: 100vw;
      max-height: 100vh;
      display: none;
      outline: none;
    }
    #status {
      text-align: center;
      color: rgba(255,255,255,0.5);
      font-size: 15px;
    }
    #status .icon { font-size: 42px; margin-bottom: 14px; opacity: 0.4; }
    #back {
      position: absolute;
      top: 18px; left: 18px;
      background: rgba(255,255,255,0.1);
      border: 1px solid rgba(255,255,255,0.15);
      border-radius: 10px;
      color: #fff;
      font-size: 13px;
      padding: 8px 14px;
      text-decoration: none;
      backdrop-filter: blur(8px);
      -webkit-backdrop-filter: blur(8px);
    }
  </style>
</head>
<body>

  <a href="/" id="back">&lsaquo; TesCast</a>

  <div id="status">
    <div class="icon">&#x25B6;&#xFE0F;</div>
    <div>Waiting for video&hellip;</div>
    <div style="font-size:12px;margin-top:8px;color:rgba(255,255,255,0.28)">Send a video from the TesCast app</div>
  </div>

  <video id="player" controls playsinline></video>

  <script>
    const video  = document.getElementById('player');
    const status = document.getElementById('status');

    // Poll for a video being available every 2 seconds
    // When the server has a video, /video returns 200; otherwise 404.
    let loaded = false;

    function checkForVideo() {
      if (loaded) return;
      fetch('/video', { method: 'HEAD' })
        .then(r => {
          if (r.ok) {
            loaded = true;
            status.style.display = 'none';
            video.style.display  = 'block';
            video.src = '/video?t=' + Date.now();
            video.play().catch(() => {});
          }
        })
        .catch(() => {});
    }

    // Also listen for push notification via WebSocket
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    const ws = new WebSocket(proto + '//' + location.host + '/video-events');
    ws.onmessage = function(e) {
      if (e.data === 'new-video') {
        loaded = false;
        video.src = '/video?t=' + Date.now();
        status.style.display = 'none';
        video.style.display  = 'block';
        video.play().catch(() => {});
        loaded = true;
      }
    };

    checkForVideo();
    setInterval(checkForVideo, 2500);
  </script>

</body>
</html>`;



// ─── HTTP server ──────────────────────────────────────────────────────────
const server = http.createServer((req, res) => {
  const url = req.url.split('?')[0];

  // ── POST /upload-video ──────────────────────────────────────────────────
  if (req.method === 'POST' && url === '/upload-video') {
    const chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => {
      videoBuffer      = Buffer.concat(chunks);
      videoContentType = req.headers['content-type'] || 'video/mp4';
      console.log('[+] Video uploaded:', (videoBuffer.length / 1024 / 1024).toFixed(1), 'MB');
      // Notify any open player pages
      videoViewers.forEach(ws => {
        if (ws.readyState === WebSocket.OPEN) ws.send('new-video');
      });
      res.writeHead(200, { 'Content-Type': 'text/plain' });
      res.end('OK');
    });
    req.on('error', () => { res.writeHead(500); res.end(); });
    return;
  }

  // ── GET routes ──────────────────────────────────────────────────────────
  if (req.method !== 'GET') {
    res.writeHead(405); res.end(); return;
  }

  switch (url) {

    case '/':
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(hubHTML);
      break;

    case '/mirror':
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(mirrorHTML);
      break;

    case '/player':
      res.writeHead(200, { 'Content-Type': 'text/html' });
      res.end(playerHTML);
      break;

    case '/video': {
      if (!videoBuffer) {
        res.writeHead(404, { 'Content-Type': 'text/plain' });
        res.end('No video available');
        return;
      }
      const total = videoBuffer.length;
      const range = req.headers.range;
      if (range) {
        const [startStr, endStr] = range.replace(/bytes=/, '').split('-');
        const start = parseInt(startStr, 10);
        const end   = endStr ? parseInt(endStr, 10) : total - 1;
        const chunk = end - start + 1;
        res.writeHead(206, {
          'Content-Range':  `bytes ${start}-${end}/${total}`,
          'Accept-Ranges':  'bytes',
          'Content-Length': chunk,
          'Content-Type':   videoContentType,
        });
        res.end(videoBuffer.slice(start, end + 1));
      } else {
        res.writeHead(200, {
          'Content-Length': total,
          'Content-Type':   videoContentType,
          'Accept-Ranges':  'bytes',
        });
        res.end(videoBuffer);
      }
      break;
    }

    default:
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found');
  }
});


// ─── WebSocket server ─────────────────────────────────────────────────────
const wss = new WebSocket.Server({ server });

let phoneSocket = null;
const viewers     = new Set();   // screen mirror viewers
const videoViewers = new Set();  // video player pages

wss.on('connection', (ws, req) => {
  const path = req.url;

  if (path === '/phone') {
    console.log('[+] Phone connected (mirror)');
    phoneSocket = ws;
    ws.on('message', data => {
      viewers.forEach(v => {
        if (v.readyState === WebSocket.OPEN) v.send(data);
      });
    });
    ws.on('close', () => {
      console.log('[-] Phone disconnected');
      phoneSocket = null;
    });

  } else if (path === '/view') {
    console.log('[+] Mirror viewer connected');
    viewers.add(ws);
    ws.on('close', () => {
      viewers.delete(ws);
      console.log('[-] Mirror viewer disconnected');
    });

  } else if (path === '/video-events') {
    videoViewers.add(ws);
    ws.on('close', () => videoViewers.delete(ws));

  } else {
    ws.close();
  }
});


// ─── Start ───────────────────────────────────────────────────────────────
const PORT = 3000;
server.listen(PORT, () => {
  console.log('TesCast relay running on port ' + PORT);
});
