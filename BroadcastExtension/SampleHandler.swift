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
final class SampleHandler: RPBroadcastSampleHandler, URLSessionWebSocketDelegate, @unchecked Sendable {

    // App Group + keys (must match Config.appGroup / Config.Key in the app target).
    private let appGroup       = "group.com.zekeyeagar.teslastream"
    private let kDomain        = "domain"
    private let kStreamKey     = "streamKey"
    private let kPublishSecret = "publishSecret"
    private let kBroadcasting  = "isBroadcasting"

    // Hard ceiling per frame, with margin under the relay's 1 MiB message limit.
    private let maxFrameBytes = 900 * 1024

    // ReplayKit only delivers frames when the screen changes, so a static screen
    // sends nothing. A periodic "ping" (auto-answered "pong" by the relay, never
    // forwarded to viewers) keeps the socket alive and doubles as a liveness probe:
    // no pong within `pongGrace` means the path is dead — a completed upload only
    // proves the bytes reached the local socket buffer, and a phone losing signal
    // usually fails silently rather than with an error. The one excuse is a ping
    // queued behind a frame that was already uploading, until that upload has been
    // in flight for `sendStuckAfter`.
    private let keepaliveInterval: TimeInterval = 10
    private let pongGrace: TimeInterval = 5
    private let sendStuckAfter: TimeInterval = 10

    // Reconnect: retry fast, back off to a cap, reset once the relay answers or a frame
    // gets through. URLSession would otherwise wait ~60 s on a handshake that never
    // answers, so each attempt gets `connectTimeout` — doubled after the second attempt
    // in a row that runs out of time (up to `maxConnectTimeout`), so a slow but working
    // link still connects instead of being cut off forever.
    private let backoffFloor: TimeInterval = 0.4
    private let backoffCap: TimeInterval = 2
    private let connectTimeout: TimeInterval = 3
    private let maxConnectTimeout: TimeInterval = 20

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

    // Shared state guarded by `lock` (mutated from the capture queue, the WebSocket
    // completion/delegate queue, and timers). URLSession calls are never made while
    // holding it.
    private var lock = os_unfair_lock_s()
    private var session: URLSession?
    private var socket: URLSessionWebSocketTask?
    private var keepalive: DispatchSourceTimer?
    private var epoch = 0             // bumped per connection; stale timers compare and bail
    private var connected = false     // have, or are establishing, a live socket
    private var established = false   // handshake finished; frames may be sent
    private var sending   = false     // one frame in flight at a time
    private var broadcasting = false  // between broadcastStarted and broadcastFinished
    private var sendStart: CFTimeInterval = 0   // when the in-flight frame started uploading
    private var lastInbound: CFTimeInterval = 0 // last message (a pong) from the relay
    private var backoff: TimeInterval = 0.4     // next reconnect delay (before jitter)
    private var handshakeTimeouts = 0           // consecutive attempts that never opened
    private var lastJPEG: Data?                 // newest encoded frame (resent on open / "need-frame")
    private var pendingFresh = false            // lastJPEG is a capture that hasn't been sent yet
    private var level = 2                       // index into `presets`; start light, then climb
    private var avgUpload: CFTimeInterval = 0   // EWMA of per-frame upload time (seconds)
    private var goodStreak = 0                  // consecutive fast frames (→ step up)
    private var badStreak  = 0                  // consecutive slow frames (→ step down)

    // Probe backoff: a rung that fails within `probeHold` frames of being climbed to
    // doubles the fast-frame streak needed to try it again (20 → 160), so a link that
    // wobbles around a rung's cost doesn't flip quality back and forth — and doesn't
    // keep paying the lag of re-probing a rung it can't hold. Holding any rung for
    // `probeHold` frames, or climbing on from it, resets its streak.
    private let climbStreak = 20
    private let maxClimbStreak = 160
    private let probeHold = 90                  // frames: ~3 s at 30 fps
    private lazy var climbNeed = Array(repeating: climbStreak, count: presets.count)
    private var probing = -1                    // rung just climbed to, until it holds
    private var framesAtLevel = 0

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
        let (task, session, timer) = withLock { () -> (URLSessionWebSocketTask?, URLSession?, DispatchSourceTimer?) in
            broadcasting = false; connected = false; established = false; epoch += 1
            defer { socket = nil; self.session = nil; keepalive = nil }
            return (socket, self.session, keepalive)
        }
        UserDefaults(suiteName: appGroup)?.set(false, forKey: kBroadcasting)
        timer?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    // MARK: - WebSocket

    private func connect() {
        // Atomically claim the connection so overlapping reconnects can't open two sockets.
        let claim = withLock { () -> (Int, TimeInterval)? in
            guard broadcasting, !connected else { return nil }
            connected = true; established = false; epoch += 1
            // 3, 3, 6, 12, 20 s: a black-holed attempt is still dropped fast, twice, before
            // the deadline starts growing for a link whose handshake is just slow.
            let deadline = min(connectTimeout * pow(2, Double(max(0, handshakeTimeouts - 1))), maxConnectTimeout)
            return (epoch, deadline)
        }
        guard let (epoch, deadline) = claim else { return }

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

        // The session keeps its delegate (self) alive until invalidated; every teardown
        // path invalidates it.
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        let current = withLock { () -> Bool in
            guard self.epoch == epoch else { return false }   // broadcast ended meanwhile
            self.session = session; self.socket = task
            return true
        }
        guard current else { session.invalidateAndCancel(); return }
        task.resume()
        receiveLoop(task)   // reading keeps the task healthy and surfaces disconnects
        startKeepalive(task, epoch: epoch)

        DispatchQueue.global().asyncAfter(deadline: .now() + deadline) { [weak self] in
            guard let self else { return }
            let timedOut = self.withLock { () -> Bool in
                guard self.epoch == epoch, !self.established else { return false }
                self.handshakeTimeouts += 1
                return true
            }
            if timedOut { self.dropAndReconnect(task) }
        }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didOpenWithProtocol protocol: String?) {
        let opened = withLock { () -> Bool in
            guard webSocketTask === socket else { return false }
            established = true
            handshakeTimeouts = 0
            lastInbound = CACurrentMediaTime()
            return true
        }
        // The relay drops its copy of the screen when the old socket closes (and has none
        // at the start): send the newest frame now — including one captured while this
        // socket was opening — instead of leaving the car waiting for the screen to change.
        if opened { upload(nil) }
    }

    private func startKeepalive(_ task: URLSessionWebSocketTask, epoch: Int) {
        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now() + keepaliveInterval, repeating: keepaliveInterval)
        timer.setEventHandler { [weak self] in self?.ping(task, epoch: epoch) }
        timer.resume()
        let replaced = withLock { () -> DispatchSourceTimer? in
            guard self.epoch == epoch else { return timer }   // superseded before it started
            defer { keepalive = timer }
            return keepalive
        }
        replaced?.cancel()
    }

    private func ping(_ task: URLSessionWebSocketTask, epoch: Int) {
        let pingAt = CACurrentMediaTime()
        // Only once the socket is open: until then the handshake watchdog is in charge.
        guard withLock({ self.epoch == epoch && established }) else { return }
        task.send(.string("ping")) { [weak self] error in
            if error != nil { self?.dropAndReconnect(task) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + pongGrace) { [weak self] in
            guard let self else { return }
            let dead = self.withLock { () -> Bool in
                guard self.epoch == epoch, self.established else { return false }
                guard self.lastInbound < pingAt else { return false }   // the relay answered
                // Only the relay's reply proves the path: a completed upload just means the
                // bytes reached the local socket buffer. The one excuse is a ping queued
                // behind a frame that was already uploading when it was sent — and only
                // until that upload has been stuck for `sendStuckAfter`.
                if self.sending, self.sendStart < pingAt {
                    return CACurrentMediaTime() - self.sendStart > self.sendStuckAfter
                }
                return true
            }
            if dead { self.dropAndReconnect(task) }
        }
    }

    // The relay sends "pong" (recorded for the liveness check; it also proves the path,
    // so the reconnect backoff resets) and "need-frame" when a car joins while it holds
    // no frame (after hibernating on a static screen). The loop trips a reconnect when
    // the socket dies, and is bound to its own task so a replaced socket's final
    // failure can't tear down the new one.
    private func receiveLoop(_ task: URLSessionWebSocketTask) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let message):
                let current = self.withLock { () -> Bool in
                    guard task === self.socket else { return false }
                    self.lastInbound = CACurrentMediaTime()
                    self.backoff = self.backoffFloor
                    return true
                }
                if current, case .string("need-frame") = message { self.resendLastFrame() }
                self.receiveLoop(task)
            case .failure:
                self.dropAndReconnect(task)
            }
        }
    }

    /// Tear down `task`'s connection and schedule a reconnect — only if `task` is still
    /// the current socket, so late callbacks from an old one are ignored.
    private func dropAndReconnect(_ task: URLSessionWebSocketTask) {
        let teardown = withLock { () -> (URLSession?, DispatchSourceTimer?, TimeInterval)? in
            guard task === socket else { return nil }
            connected = false; established = false; sending = false; epoch += 1
            defer { socket = nil; session = nil; keepalive = nil }
            let delay = backoff * Double.random(in: 1...1.25)
            backoff = min(backoff * 2, backoffCap)
            return (session, keepalive, delay)
        }
        guard let (oldSession, oldTimer, delay) = teardown else { return }
        oldTimer?.cancel()
        task.cancel(with: .abnormalClosure, reason: nil)
        oldSession?.invalidateAndCancel()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.connect()
        }
    }

    // MARK: - Frames

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with type: RPSampleBufferType) {
        guard type == .video else { return }   // audio goes over Bluetooth, not this socket

        // Drop this frame while a send is in flight. While the socket is still opening,
        // keep encoding: `upload` holds the newest frame and sends it the moment the socket
        // opens. (Sending into the handshake would time the handshake as upload time and
        // knock the quality ladder down on every reconnect.)
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
                stepLocked(to: level - 1); badStreak = max(badStreak, 1)
                return true
            }
            guard stepped else { return }
            preset = withLock { presets[level] }
            guard let smaller = encodeJPEG(pixelBuffer, orientation: orientation, preset: preset) else { return }
            jpeg = smaller
        }

        lastSent = now
        upload(jpeg)
    }

    /// The relay lost its copy of the screen (it hibernated while the screen was static)
    /// and a car just joined: send the newest frame again rather than leave the car
    /// waiting for the screen to change. Skipped if a frame is already on its way.
    private func resendLastFrame() {
        upload(nil)
    }

    /// Send a frame if the socket is open and nothing else is in flight, and feed the
    /// upload time to the quality ladder. `capture` is a newly encoded frame; nil resends
    /// the newest one. The newest frame is always read under the lock at the moment the
    /// upload is claimed, so a resend can never send an older frame after a newer one. A
    /// capture that can't go now is held and sent when the socket opens or the current
    /// upload finishes.
    private func upload(_ capture: Data?) {
        let claimed = withLock { () -> (URLSessionWebSocketTask, Data, CFTimeInterval)? in
            if let capture { lastJPEG = capture }
            guard let jpeg = lastJPEG else { return nil }
            guard established, !sending, let socket else {
                if capture != nil { pendingFresh = true }
                return nil
            }
            sending = true; sendStart = CACurrentMediaTime(); pendingFresh = false
            return (socket, jpeg, sendStart)
        }
        guard let (task, jpeg, started) = claimed else { return }
        task.send(.data(jpeg)) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.dropAndReconnect(task)
                return
            }
            let done = CACurrentMediaTime()
            let sendNewer = self.withLock { () -> Bool in
                guard task === self.socket else { return false }   // a reconnect already reset state
                self.adaptLocked(uploadTime: done - started)
                self.sending = false
                self.backoff = self.backoffFloor
                return self.pendingFresh
            }
            if sendNewer { self.upload(nil) }
        }
    }

    /// Tune the quality level from how long the last frame took to clear the socket. With
    /// one frame in flight, that time ≈ frameBytes / uplink bandwidth. Fast sends → spare
    /// headroom (climb, slowly); slow sends → saturation (drop, quickly). Asymmetric like
    /// TCP's AIMD so it settles instead of oscillating. Tuned for latency: anything slower
    /// than one frame interval is already falling behind, and one very slow frame drops a
    /// rung at once rather than waiting for the average. Caller holds `lock`.
    private func adaptLocked(uploadTime: CFTimeInterval) {
        let interval = 1.0 / targetFPS
        let fastPath = interval * 2.5
        framesAtLevel += 1
        if framesAtLevel >= probeHold {              // this rung holds: forget its failed probes
            climbNeed[level] = climbStreak
            if probing == level { probing = -1 }
        }
        // One stall (a handover, a retransmit) already costs its rung via the fast path;
        // clamping it here keeps it from dragging the average down more rungs after.
        let sample = min(uploadTime, fastPath)
        // The first sample seeds the average at no more than one interval, so a stall on
        // the very first upload costs its one rung like any other.
        avgUpload = avgUpload == 0 ? min(sample, interval) : avgUpload * 0.8 + sample * 0.2
        if uploadTime > fastPath, level > 0 {       // a single ~83 ms+ frame: congestion now
            stepLocked(to: level - 1); badStreak = 1
        } else if avgUpload > interval {             // can't keep up → lighten fast
            goodStreak = 0
            // Only a frame that was itself slow counts; a fast one means it is recovering.
            if level > 0, uploadTime > interval {
                badStreak += 1
                if badStreak >= 2 {
                    stepLocked(to: level - 1)
                    badStreak = 1   // stay primed: one more slow frame steps again
                }
            }
        } else if avgUpload < interval * 0.55 {      // comfortable headroom → sharpen slowly
            badStreak = 0
            if level < presets.count - 1 {
                goodStreak += 1
                if goodStreak >= climbNeed[level + 1] { stepLocked(to: level + 1) }
            }
        } else {
            goodStreak = 0; badStreak = 0
        }
    }

    /// Move the ladder to `newLevel`, carrying the upload-time average over instead of
    /// discarding it: JPEG size scales roughly with pixel area × quality, so the average
    /// is rescaled by that ratio and the next frame refines it. Caller holds `lock`.
    private func stepLocked(to newLevel: Int) {
        if probing == level {
            if newLevel < level {                  // the probe failed: wait longer next time
                climbNeed[level] = min(climbNeed[level] * 2, maxClimbStreak)
            } else {                               // it held well enough to climb on from
                climbNeed[level] = climbStreak
            }
        }
        probing = newLevel > level ? newLevel : -1
        let from = presets[level], to = presets[newLevel]
        avgUpload *= Double((to.width * to.width * to.quality) / (from.width * from.width * from.quality))
        level = newLevel
        goodStreak = 0
        framesAtLevel = 0
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
