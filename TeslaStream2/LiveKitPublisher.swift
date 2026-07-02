import Foundation
import Combine
import LiveKit

/// Owns the LiveKit `Room` for WebRTC screen streaming (Milestone 2).
///
/// IMPORTANT (LiveKit iOS model): the broadcast **extension** does not publish —
/// this app does. The extension forwards frames over an App-Group socket; the app
/// (holding this Room) publishes them. So the app must stay alive in the background
/// while the user is in another app — enabled by `UIBackgroundModes = audio` +
/// LiveKit's managed audio session (see the app Info.plist / Background Modes).
///
/// NOTE: these are LiveKit Swift SDK 2.x APIs. Add the `client-sdk-swift` package
/// in Xcode first (see the M2 setup notes). If a symbol mismatches your exact SDK
/// version, adjust here — the shapes below match the current docs.
@MainActor
final class LiveKitPublisher: ObservableObject {

    static let shared = LiveKitPublisher()

    @Published private(set) var connected = false

    let room: Room

    private init() {
        room = Room(roomOptions: RoomOptions(
            // Route screen capture through the broadcast upload extension, and
            // capture in-app audio so video has sound with A/V sync.
            defaultScreenShareCaptureOptions: ScreenShareCaptureOptions(
                dimensions: .h1440_169,   // 1440p capture — sharper than the 1080p default
                appAudio: true,
                useBroadcastExtension: true
            ),
            // Force H.264 — the codec Tesla's Chromium hardware-decodes on both
            // MCU2 (Intel) and MCU3 (Ryzen).
            // High bitrate for sharp 1080p screen content; single layer (no simulcast)
            // since there's one full-screen viewer.
            defaultVideoPublishOptions: VideoPublishOptions(
                screenShareEncoding: VideoEncoding(maxBitrate: 14_000_000, maxFps: 30),
                simulcast: false,
                preferredCodec: .h264
            ),
            adaptiveStream: false,
            dynacast: false
        ))
    }

    /// Fetch a publish token and connect. The screen track auto-publishes once the
    /// user starts the broadcast (LiveKit `BroadcastManager.shouldPublishTrack` default).
    func connect() async {
        guard !connected else { return }
        // We don't use the real mic (micVolume 0), so disable voice processing. This
        // drops iOS's call-like audio mode, so the phone's volume buttons can mute its
        // own speaker normally. Must be set before the audio engine starts.
        try? AudioManager.shared.setVoiceProcessingEnabled(false)
        let sm = StreamManager.shared
        guard let tokenURL = Config.tokenURL(code: sm.streamKey, role: "publish", secret: sm.publishSecret) else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: tokenURL)
            let resp = try JSONDecoder().decode(TokenResponse.self, from: data)
            try await room.connect(url: resp.wsUrl, token: resp.token)
            connected = true

            // App audio from the broadcast is MIXED into the microphone track, so we
            // publish a mic track — then silence the REAL mic (micVolume 0) so only the
            // mirrored app's sound is sent, not the phone's surroundings (no feedback).
            // Volumes MUST be set AFTER the mic engine starts, or they get reset.
            // Publish RAW audio — turn off echo-cancel / auto-gain / noise-suppression.
            // Those are for voice calls; on media they suppress music/ambience and push
            // speech forward. We don't need them (the real mic is muted below anyway).
            try? await room.localParticipant.setMicrophone(
                enabled: true,
                captureOptions: AudioCaptureOptions(
                    echoCancellation: false,
                    autoGainControl: false,
                    noiseSuppression: false
                )
            )
            AudioManager.shared.mixer.appVolume = 1
            AudioManager.shared.mixer.micVolume = 0
        } catch {
            print("[LiveKitPublisher] connect failed: \(error)")
            connected = false
        }
    }

    func disconnect() async {
        await room.disconnect()
        connected = false
    }

    private struct TokenResponse: Decodable {
        let wsUrl: String
        let token: String
    }
}
