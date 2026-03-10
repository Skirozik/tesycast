import ReplayKit
import AVFoundation
import Foundation
import UIKit

class SampleHandler: RPBroadcastSampleHandler {

    private let ciContext = CIContext()
    private var isSending = false
    private var lastSentTime: TimeInterval = 0
    private let minInterval: TimeInterval = 0.15 // ~6-7 fps — keeps latency low

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let defaults = UserDefaults(suiteName: "group.com.simeon.teslastream")
        defaults?.set(true, forKey: "broadcastActive")
        defaults?.set(Date(), forKey: "broadcastStartTime")
    }

    override func broadcastFinished() {
        let defaults = UserDefaults(suiteName: "group.com.simeon.teslastream")
        defaults?.set(false, forKey: "broadcastActive")
    }

    // MARK: - Frame processing

    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        guard sampleBufferType == .video, !isSending else { return }

        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastSentTime >= minInterval else { return }

        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Read device orientation from ReplayKit's per-frame attachment.
        // CIImage uses Y-up coordinates (opposite of screen Y-down), so .left/.right
        // rotations are visually inverted — swap them to get the correct screen rotation.
        var ciImage = CIImage(cvImageBuffer: imageBuffer)
        if let raw = CMGetAttachment(sampleBuffer,
                                     key: RPVideoSampleOrientationKey as CFString,
                                     attachmentModeOut: nil) as? NSNumber,
           let orientation = CGImagePropertyOrientation(rawValue: raw.uint32Value) {
            let corrected: CGImagePropertyOrientation
            switch orientation {
            case .left:          corrected = .right
            case .right:         corrected = .left
            case .leftMirrored:  corrected = .rightMirrored
            case .rightMirrored: corrected = .leftMirrored
            default:             corrected = orientation
            }
            ciImage = ciImage.oriented(corrected)
        }

        // Scale down 50% — halves transfer size and encoding time
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return }
        guard let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.4) else { return }

        isSending = true
        lastSentTime = now

        // Write to shared container — LocalServer watches this file and serves it as MJPEG
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.simeon.teslastream"
        ) {
            try? jpeg.write(to: containerURL.appendingPathComponent("latest_frame.jpg"), options: .atomic)
        }

        isSending = false
    }
}
