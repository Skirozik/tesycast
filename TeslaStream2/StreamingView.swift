import SwiftUI
import ReplayKit

struct StreamingView: View {

    @StateObject private var streamManager = StreamManager.shared
    @State private var elapsedTime: Int = 0
    @State private var timer: Timer? = nil

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(streamManager.isStreaming ? Color.red : Color.gray)
                        .frame(width: 12, height: 12)
                    Text(streamManager.isStreaming ? "LIVE" : "READY")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundStyle(streamManager.isStreaming ? .red : .gray)
                }

                Text(timeString(elapsedTime))
                    .font(.system(size: 48, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white)

                Text(streamManager.streamURL)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()

                BroadcastPickerView()
                    .frame(width: 60, height: 60)

                Text(streamManager.isStreaming
                     ? "Tap above to stop broadcast"
                     : "Tap above to start broadcasting your screen")
                    .font(.caption)
                    .foregroundStyle(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
                    .frame(height: 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onChange(of: streamManager.isStreaming) { streaming in
            if streaming {
                startTimer()
            } else {
                stopTimer()
            }
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        elapsedTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsedTime = 0
    }

    private func timeString(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

struct BroadcastPickerView: UIViewRepresentable {
    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = "com.simeon.TeslaStream2.BroadcastExtension"
        picker.showsMicrophoneButton = false

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
