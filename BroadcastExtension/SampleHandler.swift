import ReplayKit
import HaishinKit
import AVFoundation
import Combine

class SampleHandler: RPBroadcastSampleHandler {

    // This is the streaming engine
    private let connection = RTMPConnection()
    private var stream: RTMPStream?

    // This reads the shared IP address from the main app
    private var localIP: String {
        let defaults = UserDefaults(suiteName: "group.com.yourname.teslastream")
        return defaults?.string(forKey: "localIP") ?? "192.168.1.100"
    }

    // Called when user taps "Start Broadcast"
    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        setupAudioSession()

        let rtmpStream = RTMPStream(connection: connection)
        self.stream = rtmpStream

        // Video settings — optimized for low lag
        rtmpStream.videoSettings = VideoCodecSettings(
            videoSize: CGSize(width: 1280, height: 720),
            bitRate: 2_000_000
        )


        // Connect and start publishing
        connection.connect("rtmp://\(localIP)/live")
        rtmpStream.publish("screen")
    }

    // Called when user stops broadcast
    override func broadcastFinished() {
        stream?.close()
        connection.close()
    }

    // Called for every frame captured — this is where screen data flows
    override func processSampleBuffer(
        _ sampleBuffer: CMSampleBuffer,
        with sampleBufferType: RPSampleBufferType
    ) {
        switch sampleBufferType {
        case .video:
            // Send video frame to stream
            stream?.append(sampleBuffer, track: 0)
        case .audioApp:
            // Send app audio to stream
            stream?.append(sampleBuffer, track: 1)
        case .audioMic:
            // Send microphone audio to stream
            stream?.append(sampleBuffer, track: 1)
        @unknown default:
            break
        }
    }

    // MARK: - Audio Session
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playAndRecord,
                mode: .default,
                options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers]
            )
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
}
