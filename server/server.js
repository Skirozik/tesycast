const http = require('http');
const WebSocket = require('ws');

// HTML page served to the Tesla browser
const html = `<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>TeslaStream</title>
<style>
* { margin: 0; padding: 0; box-sizing: border-box; }
body { background: #000; width: 100vw; height: 100vh; display: flex; align-items: center; justify-content: center; overflow: hidden; }
canvas { max-width: 100vw; max-height: 100vh; }
#msg { color: #555; font-family: -apple-system, sans-serif; font-size: 16px; position: absolute; }
</style>
</head>
<body>
<span id="msg">Waiting for broadcast\u2026</span>
<canvas id="c"></canvas>
<script>
const canvas = document.getElementById('c');
const ctx = canvas.getContext('2d');
const msg = document.getElementById('msg');

const ws = new WebSocket('ws://' + location.host + '/view');
ws.binaryType = 'arraybuffer';

ws.onmessage = function(event) {
  msg.style.display = 'none';
  const blob = new Blob([event.data], { type: 'image/jpeg' });
  const url = URL.createObjectURL(blob);
  const img = new Image();
  img.onload = function() {
    canvas.width = img.naturalWidth;
    canvas.height = img.naturalHeight;
    ctx.drawImage(img, 0, 0);
    URL.revokeObjectURL(url);
  };
  img.src = url;
};

ws.onclose = function() {
  msg.textContent = 'Disconnected — refresh to reconnect';
  msg.style.display = 'block';
};
</script>
</body>
</html>`;

// HTTP server — serves the viewer page
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/html' });
  res.end(html);
});

// WebSocket server — relays frames from phone to viewer
const wss = new WebSocket.Server({ server });

let phoneSocket = null;
const viewers = new Set();

wss.on('connection', (ws, req) => {
  const path = req.url;

  if (path === '/phone') {
    console.log('[+] Phone connected');
    phoneSocket = ws;

    ws.on('message', (data) => {
      // Relay each JPEG frame to all connected Tesla browsers
      viewers.forEach((viewer) => {
        if (viewer.readyState === WebSocket.OPEN) {
          viewer.send(data);
        }
      });
    });

    ws.on('close', () => {
      console.log('[-] Phone disconnected');
      phoneSocket = null;
    });

  } else if (path === '/view') {
    console.log('[+] Viewer connected');
    viewers.add(ws);

    ws.on('close', () => {
      viewers.delete(ws);
      console.log('[-] Viewer disconnected');
    });

  } else {
    ws.close();
  }
});

const PORT = 80;
server.listen(PORT, () => {
  console.log('TeslaStream relay running on port ' + PORT);
});
