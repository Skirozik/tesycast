import ReplayKit
import CoreImage
import CoreMedia
import CoreVideo
import ImageIO
import QuartzCore
import os

/// Broadcast extension — MJPEG-over-WebSocket screen push (compatibility path).
///
/// WHY THIS EXISTS: Tesla's in-car browser will not reliably decode video. A plain
/// H.264 MP4 opened directly in the browser (nothing to do with this app) plays a
/// frame then freezes — Tesla deliberately cripples the browser's video-codec layer.
/// WebRTC/HTML5 `<video>` therefore always stalls on the car, no matter the bitrate.
///
/// The workaround is to send NO video at all: encode each captured screen frame as a
/// downscaled JPEG and stream the stills over a WebSocket to the relay's `/ingest`
/// endpoint. The Tesla page paints them onto a `<canvas>` (see server.js `mirrorHTML`),
/// which is plain image drawing — it never touches the video decoder, so Tesla has
/// nothing to freeze. Audio is not carried here; it rides Bluetooth from the phone to
/// the car speakers like normal media playback.
///
/// This is a plain `RPBroadcastSampleHandler` (no LiveKit): LiveKit's `LKSampleHandler`
/// lifecycle methods aren't `open`, so a single extension can't branch between the two
/// transports — and since the car can't play WebRTC video anyway, this is the path.
///
/// Config (domain / streamKey / publishSecret) comes from the shared App Group, written
/// by the app's `StreamManager.syncToAppGroup()`. Keys are duplicated here as literals
/// because the extension can't import the app-target `Config`.
///
/// The relay runs on Cloudflare Workers, which closes a WebSocket on any message over
/// 1 MiB, so every frame is checked against `maxFrameBytes` before it is sent.
final class SampleHandler: RPBroadcastSampleHandler, @unchecked Sendable {

    // App Group + keys (must match Config.appGroup / Config.Key in the app target).
    private let appGroup       = "group.com.zekeyeagar.teslastream"
    private let kDomain        = "domain"
    private let kStreamKey     = "streamKey"
    private let kPublishSecret = "publishSecret"
    private let kBroadcasting  = "isBroadcasting"

    // Networking
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var keepalive: DispatchSourceTimer?

    // Hard ceiling per frame, with margin under the relay's 1 MiB message limit.
    private let maxFrameBytes = 900 * 1024

    // ReplayKit only delivers frames when the screen changes, so a static screen
    // sends nothing. The relay reaps sockets silent for ~150 s; a periodic "ping"
    // (auto-answered by the relay, never forwarded to viewers) keeps it alive.
    private let keepaliveInterval: TimeInterval = 25

    // Frame pacing. Only ONE frame is uploaded at a time (see `sending`), so the effective
    // frame rate is capped both here and by how fast a single JPEG clears the uplink.
    private let targetFPS: Double = 30
    private var lastSent: CFTimeInterval = 0   // touched only on the capture queue

    // Adaptive quality ladder (see `adapt(uploadTime:)`). We climb toward sharper presets
    // when uploads are fast (spare bandwidth) and drop to lighter ones when they're slow
    // (saturated), so the stream self-tunes: sharp on Wi-Fi, smooth + low-latency on LTE.
    // Immutable config; the current index `level` is the mutable, lock-guarded part below.
    private let presets: [(width: CGFloat, quality: CGFloat)] = [
        (420, 0.34), (540, 0.36), (660, 0.40), (800, 0.44), (960, 0.48), (1200, 0.52),
    ]

    // JPEG encoding (reused across frames to avoid per-frame allocation).
    private let ciContext  = CIContext(options: [.useSoftwareRenderer: false])
    private let colorSpace = CGColorSpaceCreateDeviceRGB()

    // Shared state guarded by `lock` (mutated from both the capture queue and the
    // WebSocket completion queue).
    private var lock = os_unfair_lock_s()
    private var connected = false     // have, or are establishing, a live socket
    private var sending   = false     // one frame in flight at a time
    private var broadcasting = false  // between broadcastStarted and broadcastFinished
    private var level = 2                       // index into `presets`; start light, then climb
    private var avgUpload: CFTimeInterval = 0   // EWMA of per-frame upload time (seconds)
    private var goodStreak = 0                  // consecutive fast frames (→ step up)
    private var badStreak  = 0                  // consecutive slow frames (→ step down)

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return body()
    }

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        withLock { broadcasting = true }
        UserDefaults(suiteName: appGroup)?.set(true, forKey: kBroadcasting)
        connect()
    }

    override func broadcastFinished() {
        withLock { broadcasting = false; connected = false }
        UserDefaults(suiteName: appGroup)?.set(false, forKey: kBroadcasting)
        keepalive?.cancel()
        keepalive = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - WebSocket

    private func connect() {
        // Atomically claim the connection so overlapping reconnects can't open two sockets.
        let claim = withLock { () -> Bool in
            guard broadcasting, !connected else { return false }
            connected = true
            return true
        }
        guard claim else { return }

        let d = UserDefaults(suiteName: appGroup)
        let domain = d?.string(forKey: kDomain) ?? ""
        let code   = d?.string(forKey: kStreamKey) ?? ""
        let secret = d?.string(forKey: kPublishSecret) ?? ""
        guard !domain.isEmpty, !code.isEmpty, !secret.isEmpty,
              let esc = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryValueSafe),
              let url = URL(string: "wss://\(domain)/ingest/\(code)?secret=\(esc)") else {
            withLock { connected = false }
            return
        }

        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.session = session
        self.socket = task
        task.resume()
        receiveLoop()   // reading keeps the task healthy and surfaces disconnects
        startKeepalive()
    }

    private func startKeepalive() {
        keepalive?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + keepaliveInterval, repeating: keepaliveInterval)
        timer.setEventHandler { [weak self] in
            guard let self, self.withLock({ self.connected }) else { return }
            self.socket?.send(.string("ping")) { _ in }
        }
        timer.resume()
        keepalive = timer
    }

    // We don't expect inbound messages; the receive loop exists so a dropped socket
    // trips `connected = false` and schedules a reconnect.
    private func receiveLoop() {
        socket?.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.receiveLoop()
            case .failure:
                self.dropAndReconnect()
            }
        }
    }

    private func dropAndReconnect() {
        withLock { connected = false; sending = false }
        keepalive?.cancel()
        keepalive = nil
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - Frames

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .video else { return }   // audio goes over Bluetooth, not this socket

        // Drop this frame if we're not connected or a send is already in flight.
        let proceed = withLock { connected && !sending }
        guard proceed else { return }

        // Frame-rate cap.
        let now = CACurrentMediaTime()
        guard now - lastSent >= 1.0 / targetFPS else { return }

        var preset = withLock { presets[level] }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation = orientation(of: sampleBuffer)
        guard var jpeg = encodeJPEG(pixelBuffer, orientation: orientation, preset: preset) else { return }

        // An oversized frame would get the socket closed, not just dropped. Step down
        // the ladder and re-encode; at the lightest preset just skip this frame.
        while jpeg.count > maxFrameBytes {
            let stepped = withLock { () -> Bool in
                guard level > 0 else { return false }
                level -= 1; avgUpload = 0; goodStreak = 0; badStreak = 0
                return true
            }
            guard stepped else { return }
            preset = withLock { presets[level] }
            guard let smaller = encodeJPEG(pixelBuffer, orientation: orientation, preset: preset) else { return }
            jpeg = smaller
        }

        lastSent = now
        withLock { sending = true }
        let sendStart = CACurrentMediaTime()
        socket?.send(.data(jpeg)) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.dropAndReconnect()
                return
            }
            self.adapt(uploadTime: CACurrentMediaTime() - sendStart)
            self.withLock { self.sending = false }
        }
    }

    /// Tune the quality level from how long the last frame took to clear the socket. With
    /// one frame in flight, that time ≈ frameBytes / uplink bandwidth. Fast sends → spare
    /// headroom (climb, slowly); slow sends → saturation (drop, quickly). Asymmetric like
    /// TCP's AIMD so it settles instead of oscillating. Resetting the average after a step
    /// forces a fresh read at the new frame size.
    private func adapt(uploadTime: CFTimeInterval) {
        let interval = 1.0 / targetFPS
        withLock {
            avgUpload = avgUpload == 0 ? uploadTime : avgUpload * 0.8 + uploadTime * 0.2
            if avgUpload > interval * 1.15 {          // can't keep up → lighten fast
                goodStreak = 0
                if level > 0 {
                    badStreak += 1
                    if badStreak >= 2 { level -= 1; badStreak = 0; avgUpload = 0 }
                }
            } else if avgUpload < interval * 0.55 {   // comfortable headroom → sharpen slowly
                badStreak = 0
                if level < presets.count - 1 {
                    goodStreak += 1
                    if goodStreak >= 20 { level += 1; goodStreak = 0; avgUpload = 0 }
                }
            } else {
                goodStreak = 0; badStreak = 0
            }
        }
    }

    /// ReplayKit keeps the capture buffer in the device's native orientation and reports
    /// the current screen rotation as a separate attachment. Without applying it, a video
    /// watched in landscape arrives sideways / squeezed into a vertical frame.
    private func orientation(of sampleBuffer: CMSampleBuffer) -> CGImagePropertyOrientation {
        guard let num = CMGetAttachment(sampleBuffer, key: RPVideoSampleOrientationKey as CFString, attachmentModeOut: nil) as? NSNumber,
              let reported = CGImagePropertyOrientation(rawValue: num.uint32Value) else {
            return .up
        }
        // ReplayKit reports the landscape direction such that CIImage.oriented() rotates
        // it the wrong 90° — landing 180° off (upside-down landscape). Swapping the two
        // 90° cases flips the rotation the right way; portrait (.up/.down) is unaffected.
        switch reported {
        case .left:          return .right
        case .right:         return .left
        case .leftMirrored:  return .rightMirrored
        case .rightMirrored: return .leftMirrored
        default:             return reported
        }
    }

    private func encodeJPEG(_ pixelBuffer: CVPixelBuffer,
                            orientation: CGImagePropertyOrientation,
                            preset: (width: CGFloat, quality: CGFloat)) -> Data? {
        autoreleasepool {
            var image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
            let width = image.extent.width
            if width > preset.width {
                let scale = preset.width / width
                image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            }
            let options: [CIImageRepresentationOption: Any] = [
                CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): preset.quality
            ]
            return ciContext.jpegRepresentation(of: image, colorSpace: colorSpace, options: options)
        }
    }
}

private extension CharacterSet {
    /// Query-value safe set (mirrors the app target's `urlQueryValueAllowed`, which the
    /// extension can't see). Excludes `&`, `=`, `?`, `+`, etc.
    static let urlQueryValueSafe: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
