import Foundation

/// Central configuration for the cloud relay. Baked in at build time so users
/// never type a server address. Change `domain` to your deployed relay host.
///
/// NOTE: this file is a member of the app target only (Xcode file-system
/// synchronized groups map `TeslaStream2/` to the app). The broadcast extension
/// does NOT import this — it reads `domain` / `streamKey` / `publishSecret` from
/// the shared App Group, which the app writes via `StreamManager.syncToAppGroup()`.
enum Config {

    /// TODO: set this to your real relay domain (tescast is retired).
    /// Threads into the Tesla watch URL and the extension's wss ingest URL.
    static let domain = "tesycast.com"

    /// Shared App Group bridging the app and the broadcast extension.
    static let appGroup = "group.com.zekeyeagar.teslastream"

    /// LiveKit signaling endpoint (Milestone 2). Derived from `domain`.
    static var livekitWSURL: String { "wss://lk.\(domain)" }

    /// Transport the extension should use for the current broadcast.
    enum Mode: String {
        case webrtc   // LiveKit WebRTC (primary — smooth video + audio)
        case mjpeg    // M1 fallback for Teslas where WebRTC misbehaves
    }

    // App Group keys (kept identical in SampleHandler — the extension can't import this file).
    enum Key {
        static let streamKey      = "streamKey"      // public room code (in the watch URL)
        static let publishSecret  = "publishSecret"  // private credential (never in a URL)
        static let domain         = "domain"
        static let isBroadcasting = "isBroadcasting"
        static let mode           = "mode"           // "webrtc" | "mjpeg"
    }

    /// The URL the user opens in the Tesla browser.
    static func watchURL(code: String) -> String {
        "https://\(domain)/watch/\(code)"
    }

    /// Token endpoint. `role: "publish"` needs the secret; omit for a subscribe token.
    static func tokenURL(code: String, role: String, secret: String? = nil) -> URL? {
        var s = "https://\(domain)/token/\(code)?role=\(role)"
        if let secret, let esc = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) {
            s += "&secret=\(esc)"
        }
        return URL(string: s)
    }

    /// Endpoint the app POSTs to so `/watch` serves the matching player.
    static func modeURL(code: String, mode: Mode, secret: String) -> URL? {
        guard let esc = secret.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        return URL(string: "https://\(domain)/mode/\(code)?mode=\(mode.rawValue)&secret=\(esc)")
    }
}

extension CharacterSet {
    /// Query-value safe set (excludes `&`, `=`, `?`, `+`, etc.).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
