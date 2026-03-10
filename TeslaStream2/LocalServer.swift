import Foundation
import Combine

// MARK: - HTML pages

private let hubHTML = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TesCast</title>
  <style>
    *, *::before, *::after { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      background: #04040a;
      min-height: 100vh;
      font-family: -apple-system, BlinkMacSystemFont, sans-serif;
      color: #fff;
      display: flex;
      flex-direction: column;
      align-items: center;
      overflow-x: hidden;
    }
    #wave-canvas {
      position: fixed;
      inset: 0;
      width: 100vw;
      height: 100vh;
      z-index: 0;
      pointer-events: none;
    }
    .page {
      position: relative;
      z-index: 1;
      width: 100%;
      display: flex;
      flex-direction: column;
      align-items: center;
      min-height: 100vh;
    }
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
    .card.mirror:hover { box-shadow: 0 20px 40px rgba(59,130,246,0.15); }
    .card.video:hover  { box-shadow: 0 20px 40px rgba(168,85,247,0.15); }
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
    .card.mirror .card-icon { background: rgba(59,130,246,0.14); border: 1px solid rgba(59,130,246,0.25); }
    .card.video  .card-icon { background: rgba(168,85,247,0.14); border: 1px solid rgba(168,85,247,0.25); }
    .card h2 { font-size: 18px; font-weight: 700; margin-bottom: 8px; letter-spacing: -0.2px; }
    .card p  { font-size: 13px; color: rgba(255,255,255,0.4); line-height: 1.6; }
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
    .card:hover .card-arrow { background: rgba(255,255,255,0.14); color: rgba(255,255,255,0.8); }
    .footer { margin-top: auto; padding: 28px; font-size: 12px; color: rgba(255,255,255,0.15); letter-spacing: 0.05em; }
  </style>
</head>
<body>
  <canvas id="wave-canvas"></canvas>
  <div class="page">
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
    <div class="footer">tescast &mdash; local</div>
  </div>
  <script>
    (function() {
      var canvas = document.getElementById('wave-canvas');
      var ctx = canvas.getContext('2d');
      var w, h, nt = 0;
      var COLORS = ['#3b82f6','#6366f1','#a855f7','#ec4899','#22d3ee'];
      var WAVE_COUNT = 5, WAVE_WIDTH = 60, BLUR = 12, OPACITY = 0.45, SPEED = 0.0018;
      function resize() { w = canvas.width = window.innerWidth; h = canvas.height = window.innerHeight; ctx.filter = 'blur(' + BLUR + 'px)'; }
      function noise(x, y, z) {
        var X = Math.floor(x) & 255, Y = Math.floor(y) & 255, Z = Math.floor(z) & 255;
        x -= Math.floor(x); y -= Math.floor(y); z -= Math.floor(z);
        var u = fade(x), v = fade(y), w2 = fade(z);
        return lerp(w2, lerp(v, lerp(u, grad(p[p[p[X]+Y]+Z], x, y, z), grad(p[p[p[X+1]+Y]+Z], x-1, y, z)), lerp(u, grad(p[p[p[X]+Y+1]+Z], x, y-1, z), grad(p[p[p[X+1]+Y+1]+Z], x-1, y-1, z))), lerp(v, lerp(u, grad(p[p[p[X]+Y]+Z+1], x, y, z-1), grad(p[p[p[X+1]+Y]+Z+1], x-1, y, z-1)), lerp(u, grad(p[p[p[X]+Y+1]+Z+1], x, y-1, z-1), grad(p[p[p[X+1]+Y+1]+Z+1], x-1, y-1, z-1))));
      }
      function fade(t) { return t*t*t*(t*(t*6-15)+10); }
      function lerp(t,a,b) { return a+t*(b-a); }
      function grad(h,x,y,z) { h &= 15; var u=h<8?x:y, v=h<4?y:h===12||h===14?x:z; return ((h&1)===0?u:-u)+((h&2)===0?v:-v); }
      var perm = []; for(var i=0;i<256;i++) perm[i]=i;
      for(var i=255;i>0;i--) { var j=Math.floor(Math.random()*(i+1)), tmp=perm[i]; perm[i]=perm[j]; perm[j]=tmp; }
      var p = new Array(512); for(var i=0;i<512;i++) p[i]=perm[i&255];
      function render() {
        nt += SPEED;
        ctx.fillStyle = '#04040a';
        ctx.globalAlpha = OPACITY;
        ctx.fillRect(0, 0, w, h);
        for(var i=0;i<WAVE_COUNT;i++) {
          ctx.beginPath();
          ctx.lineWidth = WAVE_WIDTH;
          ctx.strokeStyle = COLORS[i % COLORS.length];
          for(var x=0;x<w;x+=4) { var y = noise(x/900, 0.35*i, nt)*110; ctx.lineTo(x, y + h*0.5); }
          ctx.stroke(); ctx.closePath();
        }
        requestAnimationFrame(render);
      }
      resize();
      window.addEventListener('resize', resize);
      render();
    })();
  </script>
</body>
</html>
"""

private let mirrorHTML = """
<!DOCTYPE html>
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
    #feed {
      max-width: 100%;
      max-height: 100%;
      object-fit: contain;
      display: block;
    }
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
  </style>
</head>
<body>
  <a href="/" id="back">&lsaquo; TesCast</a>
  <div id="status">
    <div class="icon">&#x1F4F1;</div>
    <div>Waiting for broadcast&hellip;</div>
    <div style="font-size:12px;margin-top:8px;color:rgba(255,255,255,0.28)">Start Screen Mirror in the TesCast app</div>
  </div>
  <img id="feed" src="/stream" style="max-width:100%;max-height:100%;object-fit:contain" onload="document.getElementById('status').style.display='none'">
</body>
</html>
"""

private let playerHTML = """
<!DOCTYPE html>
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
    var video  = document.getElementById('player');
    var status = document.getElementById('status');
    var loaded = false;
    function checkForVideo() {
      if (loaded) return;
      fetch('/video', { method: 'HEAD' })
        .then(function(r) {
          if (r.ok) {
            loaded = true;
            status.style.display = 'none';
            video.style.display  = 'block';
            video.src = '/video?t=' + Date.now();
            video.play().catch(function(){});
          }
        })
        .catch(function(){});
    }
    checkForVideo();
    setInterval(checkForVideo, 2500);
  </script>
</body>
</html>
"""

// MARK: - LocalServer (POSIX sockets — works on all interfaces including hotspot)

@MainActor
final class LocalServer: ObservableObject {

    static let shared = LocalServer()
    static let port: UInt16 = 8080

    @Published var isRunning  = false
    @Published var isStreaming = false
    @Published var hasVideo   = false

    // File descriptors of live MJPEG clients
    private var mjpegFDs: [Int32] = []

    // Latest uploaded video
    private var videoData: Data?
    private var videoContentType: String = "video/mp4"

    // Server socket + accept source
    private var serverFd: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    private let ioQueue = DispatchQueue(label: "tescast.localserver.io", qos: .userInitiated)

    private init() {}

    // MARK: - Start / Stop

    func start() {
        guard serverFd < 0 else { return }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            print("[LocalServer] socket() failed: \(errno)")
            return
        }

        // Allow address reuse so restart is instant
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        // Suppress SIGPIPE on writes to disconnected clients
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        // Bind to 0.0.0.0:8080 — listens on ALL interfaces (loopback, Wi-Fi, hotspot)
        var addr = sockaddr_in()
        memset(&addr, 0, MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port   = Self.port.bigEndian
        addr.sin_addr.s_addr = INADDR_ANY

        let bindOK = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindOK == 0 else {
            print("[LocalServer] bind() failed: \(errno)")
            close(fd)
            return
        }
        guard listen(fd, 16) == 0 else {
            print("[LocalServer] listen() failed: \(errno)")
            close(fd)
            return
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.acceptClient(serverFd: fd)
        }
        source.setCancelHandler { close(fd) }
        source.resume()

        serverFd = fd
        acceptSource = source
        isRunning = true
        print("[LocalServer] Listening on 0.0.0.0:\(Self.port)")
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        serverFd = -1      // actual close is in setCancelHandler
        mjpegFDs.forEach { close($0) }
        mjpegFDs.removeAll()
        isRunning = false
    }

    // MARK: - Push JPEG frame to MJPEG clients

    func pushFrame(_ jpeg: Data) {
        isStreaming = true
        guard !mjpegFDs.isEmpty else { return }

        let boundary = "--frame\r\nContent-Type: image/jpeg\r\nContent-Length: \(jpeg.count)\r\n\r\n"
        var frame = Data()
        frame.append(boundary.data(using: .utf8)!)
        frame.append(jpeg)
        frame.append("\r\n".data(using: .utf8)!)

        let snapshot = frame
        let fds = mjpegFDs

        ioQueue.async { [weak self] in
            var dead: [Int32] = []
            for fd in fds {
                if !Self.writeFully(fd: fd, data: snapshot) {
                    dead.append(fd)
                    close(fd)
                }
            }
            if !dead.isEmpty {
                Task { @MainActor [weak self] in
                    self?.mjpegFDs.removeAll { dead.contains($0) }
                }
            }
        }
    }

    // MARK: - Accept incoming connections

    private func acceptClient(serverFd: Int32) {
        var clientAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(serverFd, $0, &addrLen)
            }
        }
        guard clientFd >= 0 else { return }

        // Suppress SIGPIPE on this socket too
        var yes: Int32 = 1
        setsockopt(clientFd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))

        ioQueue.async { [weak self] in
            self?.handleClient(fd: clientFd)
        }
    }

    // MARK: - Read request + dispatch (runs on ioQueue)

    private func handleClient(fd: Int32) {
        // Read until \r\n\r\n
        var buf = Data()
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        var tmp = [UInt8](repeating: 0, count: 4096)

        while buf.range(of: separator) == nil {
            let n = recv(fd, &tmp, tmp.count, 0)
            if n <= 0 { close(fd); return }
            buf.append(contentsOf: tmp[..<n])
            if buf.count > 32768 { close(fd); return }
        }

        guard let sepRange = buf.range(of: separator) else { close(fd); return }
        let headerData = buf[..<sepRange.lowerBound]
        let bodyStart  = Data(buf[sepRange.upperBound...])
        guard let headerStr = String(data: headerData, encoding: .utf8) else { close(fd); return }

        Task { @MainActor [weak self] in
            self?.routeRequest(headerStr: headerStr, bodyStart: bodyStart, fd: fd)
        }
    }

    // MARK: - Routing (runs on MainActor)

    private func routeRequest(headerStr: String, bodyStart: Data, fd: Int32) {
        let lines  = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { close(fd); return }
        let parts  = requestLine.components(separatedBy: " ")
        guard parts.count >= 2 else { close(fd); return }

        let method  = parts[0]
        let rawPath = parts[1]
        let path    = rawPath.components(separatedBy: "?").first ?? rawPath

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            let kv = line.components(separatedBy: ": ")
            if kv.count >= 2 { headers[kv[0].lowercased()] = kv[1...].joined(separator: ": ") }
        }

        switch (method, path) {
        case ("GET", "/"):
            sendHTML(hubHTML, fd: fd)

        case ("GET", "/mirror"):
            sendHTML(mirrorHTML, fd: fd)

        case ("GET", "/player"):
            sendHTML(playerHTML, fd: fd)

        case ("GET", "/stream"):
            startMJPEG(fd: fd)

        case ("GET", "/video"), ("HEAD", "/video"):
            serveVideo(method: method, headers: headers, fd: fd)

        case ("POST", "/upload-video"):
            let needed = Int(headers["content-length"] ?? "0") ?? 0
            receiveBody(fd: fd, accumulated: bodyStart, needed: needed) { [weak self] body in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.videoData = body
                    self.videoContentType = headers["content-type"] ?? "video/mp4"
                    self.hasVideo = true
                    self.sendSimple(200, body: "OK", fd: fd)
                }
            }

        case ("POST", "/broadcast-stop"):
            isStreaming = false
            sendSimple(200, body: "OK", fd: fd)

        default:
            sendSimple(404, body: "Not found", fd: fd)
        }
    }

    // MARK: - MJPEG keep-alive

    private func startMJPEG(fd: Int32) {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: multipart/x-mixed-replace; boundary=frame\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n"
        let data = header.data(using: .utf8)!
        ioQueue.async { [weak self] in
            if Self.writeFully(fd: fd, data: data) {
                Task { @MainActor [weak self] in
                    self?.mjpegFDs.append(fd)
                }
            } else {
                close(fd)
            }
        }
    }

    // MARK: - Video with byte-range support

    private func serveVideo(method: String, headers: [String: String], fd: Int32) {
        guard let video = videoData else {
            sendSimple(404, body: "No video available", fd: fd)
            return
        }

        let total = video.count

        if method == "HEAD" {
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: \(videoContentType)\r\nContent-Length: \(total)\r\nAccept-Ranges: bytes\r\n\r\n"
            let data = resp.data(using: .utf8)!
            ioQueue.async { Self.writeFully(fd: fd, data: data); close(fd) }
            return
        }

        var payload = Data()
        if let rangeHeader = headers["range"] {
            let rangeStr = rangeHeader.replacingOccurrences(of: "bytes=", with: "")
            let bounds = rangeStr.components(separatedBy: "-")
            let start  = Int(bounds[0]) ?? 0
            let end    = (bounds.count > 1 && !bounds[1].isEmpty) ? (Int(bounds[1]) ?? (total - 1)) : (total - 1)
            let len    = end - start + 1
            let resp = "HTTP/1.1 206 Partial Content\r\nContent-Range: bytes \(start)-\(end)/\(total)\r\nAccept-Ranges: bytes\r\nContent-Length: \(len)\r\nContent-Type: \(videoContentType)\r\n\r\n"
            payload.append(resp.data(using: .utf8)!)
            payload.append(video[start...(min(end, total - 1))])
        } else {
            let resp = "HTTP/1.1 200 OK\r\nContent-Length: \(total)\r\nContent-Type: \(videoContentType)\r\nAccept-Ranges: bytes\r\n\r\n"
            payload.append(resp.data(using: .utf8)!)
            payload.append(video)
        }

        let snapshot = payload
        ioQueue.async { Self.writeFully(fd: fd, data: snapshot); close(fd) }
    }

    // MARK: - Read full POST body (runs on ioQueue)

    private func receiveBody(
        fd: Int32,
        accumulated: Data,
        needed: Int,
        completion: @escaping @Sendable (Data) -> Void
    ) {
        ioQueue.async {
            var buf = accumulated
            var tmp = [UInt8](repeating: 0, count: 65536)
            while buf.count < needed {
                let n = recv(fd, &tmp, min(tmp.count, needed - buf.count), 0)
                if n <= 0 { break }
                buf.append(contentsOf: tmp[..<n])
            }
            completion(buf)
        }
    }

    // MARK: - Response helpers

    private func sendHTML(_ html: String, fd: Int32) {
        let body = html.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var payload = Data()
        payload.append(header.data(using: .utf8)!)
        payload.append(body)
        let snapshot = payload
        ioQueue.async { Self.writeFully(fd: fd, data: snapshot); close(fd) }
    }

    private func sendSimple(_ status: Int, body: String, fd: Int32) {
        let statusText: String
        switch status {
        case 200: statusText = "OK"
        case 404: statusText = "Not Found"
        default:  statusText = "Error"
        }
        let bodyData = body.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 \(status) \(statusText)\r\nContent-Type: text/plain\r\nContent-Length: \(bodyData.count)\r\nConnection: close\r\n\r\n"
        var payload = Data()
        payload.append(header.data(using: .utf8)!)
        payload.append(bodyData)
        let snapshot = payload
        ioQueue.async { Self.writeFully(fd: fd, data: snapshot); close(fd) }
    }

    // MARK: - Low-level write helper

    @discardableResult
    private static func writeFully(fd: Int32, data: Data) -> Bool {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { ptr in
                send(fd, ptr.baseAddress!.advanced(by: offset), data.count - offset, 0)
            }
            if n <= 0 { return false }
            offset += n
        }
        return true
    }
}
