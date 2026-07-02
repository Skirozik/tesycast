import Foundation
import Combine

@MainActor
class StreamManager: ObservableObject {

    // MARK: - Published Properties
    @Published var isStreaming = false
    @Published var streamURL = ""

    // MARK: - Identity
    /// Public room code — appears in the Tesla watch URL.
    let streamKey: String
    /// Private credential — proves publish rights to the relay/token endpoint, never in a URL.
    let publishSecret: String

    // MARK: - Transport mode
    /// When true, broadcasts use the M1 MJPEG fallback instead of WebRTC (for older Teslas).
    @Published var compatibilityMode: Bool {
        didSet {
            UserDefaults.standard.set(compatibilityMode, forKey: "compatibilityMode")
            syncToAppGroup()
        }
    }
    var mode: Config.Mode { compatibilityMode ? .mjpeg : .webrtc }

    // MARK: - Private Properties
    private var broadcastMonitor: Timer?

    // MARK: - Singleton
    static let shared = StreamManager()

    private init() {
        // Persistent per-install stream key (the room code).
        let keyName = "userStreamKey"
        if let existing = UserDefaults.standard.string(forKey: keyName) {
            self.streamKey = existing
        } else {
            let newKey = Self.randomToken(12)
            UserDefaults.standard.set(newKey, forKey: keyName)
            self.streamKey = newKey
        }

        // Persistent per-install publish secret.
        let secretName = "userPublishSecret"
        if let existing = UserDefaults.standard.string(forKey: secretName) {
            self.publishSecret = existing
        } else {
            let newSecret = Self.randomToken(24)
            UserDefaults.standard.set(newSecret, forKey: secretName)
            self.publishSecret = newSecret
        }

        self.compatibilityMode = UserDefaults.standard.bool(forKey: "compatibilityMode")

        updateStreamURL()
        syncToAppGroup()
        startBroadcastMonitoring()
    }

    // MARK: - Token generation
    private static func randomToken(_ length: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")
        var token = ""
        for _ in 0..<length {
            token.append(alphabet[Int.random(in: 0..<alphabet.count)])
        }
        return token
    }

    // MARK: - Stream URL (shown to the user for the Tesla browser)
    private func updateStreamURL() {
        streamURL = Config.watchURL(code: streamKey)
    }

    // MARK: - Share config with BroadcastExtension via App Group
    func syncToAppGroup() {
        let defaults = UserDefaults(suiteName: Config.appGroup)
        defaults?.set(Config.domain, forKey: Config.Key.domain)
        defaults?.set(streamKey, forKey: Config.Key.streamKey)
        defaults?.set(publishSecret, forKey: Config.Key.publishSecret)
        defaults?.set(mode.rawValue, forKey: Config.Key.mode)
    }

    /// Tell the relay which transport this broadcast will use, so `/watch` serves the
    /// matching player. Call before starting a broadcast.
    func postMode() async {
        guard let url = Config.modeURL(code: streamKey, mode: mode, secret: publishSecret) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        _ = try? await URLSession.shared.data(for: req)
    }

    // MARK: - Broadcast State Monitoring
    private func startBroadcastMonitoring() {
        broadcastMonitor = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            let broadcasting = UserDefaults(suiteName: Config.appGroup)?.bool(forKey: Config.Key.isBroadcasting) ?? false
            Task { @MainActor [weak self] in
                self?.isStreaming = broadcasting
            }
        }
    }
}
