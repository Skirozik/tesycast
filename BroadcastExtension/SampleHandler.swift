import ReplayKit
import AVFoundation
import Foundation
import UIKit

class SampleHandler: RPBroadcastSampleHandler {

    private var webSocketTask: URLSessionWebSocketTask?
    private let ciContext = CIContext()
    private var isSending = false
    private var lastSentTime: TimeInterval = 0
    private let minInterval: TimeInterval = 0.15 // ~6-7 fps — keeps latency low

    // MARK: - Lifecycle

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        let defaults = UserDefaults(suiteName: "group.com.simeon.teslastream")
        defaults?.set(true, forKey: "broadcastActive")
        defaults?.set(Date(), forKey: "broadcastStartTime")
        connectWebSocket()
    }

    override func broadcastFinished() {
        let defaults = UserDefaults(suiteName: "group.com.simeon.teslastream")
        defaults?.set(false, forKey: "broadcastActive")
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
        let url = URL(string: "wss://tescast.com/phone")!
        webSocketTask = URLSession.shared.webSocketTask(with: url)
        webSocketTask?.resume()
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

        // Scale down 50% — halves transfer size and encoding time
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: 0.5, y: 0.5))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return }
        guard let jpeg = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.4) else { return }

        // Write to shared container so the main app can show broadcast status
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.com.simeon.teslastream"
        ) {
            try? jpeg.write(to: containerURL.appendingPathComponent("latest_frame.jpg"))
        }

        isSending = true
        lastSentTime = now
        webSocketTask?.send(.data(jpeg)) { [weak self] error in
            self?.isSending = false
            if error != nil {
                self?.connectWebSocket()
            }
        }
    }
}
