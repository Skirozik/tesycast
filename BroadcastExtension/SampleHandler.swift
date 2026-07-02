import LiveKit

/// WebRTC screen capture for the broadcast upload extension.
///
/// `LKSampleHandler` captures the ReplayKit frames and forwards them over a
/// Unix-domain socket in the App Group to the main app, which owns the LiveKit
/// `Room` and publishes them to the SFU. It reads `RTCAppGroupIdentifier` from
/// this extension's Info.plist to find that socket.
///
/// LiveKit's lifecycle methods (`broadcastStarted` / `processSampleBuffer` /
/// `broadcastFinished`) are `public`, not `open`, so they can't be overridden
/// here — the SDK handles them. We only override logging.
final class SampleHandler: LKSampleHandler, @unchecked Sendable {
    override var enableLogging: Bool { true }
}
