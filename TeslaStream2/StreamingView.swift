import SwiftUI
import ReplayKit

struct StreamingView: View {

    @StateObject private var streamManager = StreamManager.shared
    @State private var elapsedTime: Int = 0
    @State private var elapsedTimer: Timer? = nil
    @State private var statusTimer: Timer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {

                Spacer()

                // LIVE indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(streamManager.isStreaming ? Color.red : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(streamManager.isStreaming ? "LIVE" : "READY")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(streamManager.isStreaming ? .red : .gray)
                }

                // Timer
                Text(timeString(elapsedTime))
                    .font(.system(size: 48, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white)

                // Stream URL
                Text(streamManager.streamURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                // Broadcast Picker Button
                BroadcastPickerView()
                    .frame(width: 60, height: 60)

                Text(streamManager.isStreaming ? "Tap above to stop broadcast" : "Tap above to start broadcasting your screen")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
                    .frame(height: 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            // Tell the relay which player to serve, and (WebRTC mode) connect the
            // LiveKit room now so the screen track auto-publishes when the user
            // starts the broadcast.
            Task {
                await streamManager.postMode()
                if !streamManager.compatibilityMode {
                    await LiveKitPublisher.shared.connect()
                }
            }
            // In image (MJPEG) mode the extension owns the connection, so the app can't
            // see the LiveKit broadcast state. Poll the relay's presence signal instead
            // so LIVE/READY and the timer reflect whether frames are actually arriving.
            if streamManager.compatibilityMode {
                statusTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
                    Task { await pollStatus() }
                }
            }
        }
        .onDisappear {
            elapsedTimer?.invalidate()
            elapsedTimer = nil
            statusTimer?.invalidate()
            statusTimer = nil
        }
        .onChange(of: streamManager.isStreaming) { nowStreaming in
            if nowStreaming {
                elapsedTime = 0
                elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    elapsedTime += 1
                }
            } else {
                elapsedTimer?.invalidate()
                elapsedTimer = nil
                elapsedTime = 0
                Task { await LiveKitPublisher.shared.disconnect() }
            }
        }
    }

    /// Ask the relay whether our publisher socket is connected; mirror that to the
    /// LIVE badge/timer. Only used in image (MJPEG) mode.
    @MainActor
    private func pollStatus() async {
        guard let url = Config.statusURL(code: streamManager.streamKey),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let status = try? JSONDecoder().decode(RelayStatus.self, from: data) else { return }
        if streamManager.isStreaming != status.publisher {
            streamManager.isStreaming = status.publisher
        }
    }

    private struct RelayStatus: Decodable {
        let publisher: Bool
        let viewers: Int
    }

    func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// Apple's official broadcast picker button
struct BroadcastPickerView: UIViewRepresentable {

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = "com.zekeyeagar.TeslaStream2.BroadcastExtension"
        picker.showsMicrophoneButton = true

        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.imageView?.tintColor = .white
                button.tintColor = .white
                button.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
                button.layer.cornerRadius = 30
            }
        }

        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

#Preview {
    NavigationStack {
        StreamingView()
    }
}
