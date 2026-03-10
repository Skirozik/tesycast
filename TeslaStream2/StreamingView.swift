import SwiftUI
import ReplayKit

struct StreamingView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var streamManager = StreamManager.shared
    @State private var elapsedTime: Int = 0
    @State private var timer: Timer? = nil

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.14), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            // Live glow
            if streamManager.isStreaming {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 320, height: 320)
                    .blur(radius: 90)
                    .offset(y: -120)
                    .allowsHitTesting(false)
            }

            VStack(spacing: 0) {
                Spacer()

                // Status pill
                HStack(spacing: 8) {
                    Circle()
                        .fill(streamManager.isStreaming ? Color.red : Color.white.opacity(0.35))
                        .frame(width: 8, height: 8)
                        .shadow(color: streamManager.isStreaming ? .red : .clear, radius: 6)
                    Text(streamManager.isStreaming ? "LIVE" : "READY")
                        .font(.caption).fontWeight(.bold)
                        .foregroundStyle(streamManager.isStreaming ? .red : Color.white.opacity(0.5))
                        .tracking(1.5)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(
                        streamManager.isStreaming ? Color.red.opacity(0.3) : Color.white.opacity(0.1),
                        lineWidth: 1
                    )
                )

                // Timer
                Text(timeString(elapsedTime))
                    .font(.system(size: 56, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.top, 32)
                    .padding(.bottom, 16)

                // Hotspot setup steps
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 12) {
                        Text("1")
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                        Text("Enable iPhone Personal Hotspot")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Text("2")
                            .font(.caption).fontWeight(.bold)
                            .foregroundStyle(Color.white.opacity(0.5))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.08))
                            .clipShape(Circle())
                        Text("Connect Tesla Wi-Fi to your hotspot")
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.55))
                    }
                }
                .padding(18)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 8)

                // URL card
                VStack(alignment: .leading, spacing: 8) {
                    Text("OPEN IN TESLA BROWSER")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.white.opacity(0.3))
                        .tracking(1.2)
                    Text(streamManager.mirrorURL)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .padding(18)
                .background {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
                }
                .padding(.horizontal, 28)
                .padding(.top, 0)

                Spacer()

                // Broadcast button
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(streamManager.isStreaming ? Color.red.opacity(0.14) : Color.white.opacity(0.07))
                            .frame(width: 88, height: 88)
                            .overlay(
                                Circle()
                                    .stroke(
                                        streamManager.isStreaming ? Color.red.opacity(0.35) : Color.white.opacity(0.12),
                                        lineWidth: 1
                                    )
                            )
                        BroadcastPickerView()
                            .frame(width: 88, height: 88)
                    }

                    Text(streamManager.isStreaming
                         ? "Tap above to stop broadcast"
                         : "Tap above to start broadcasting your screen")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.42))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer().frame(height: 52)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .onAppear {
            StreamManager.shared.startServer()
        }
        .onDisappear {
            StreamManager.shared.stopServer()
            stopTimer()
        }
        .onChange(of: streamManager.isStreaming) { streaming in
            if streaming {
                startTimer()
            } else {
                stopTimer()
            }
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
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 88, height: 88))
        picker.preferredExtension = "com.simeon.TeslaStream2.BroadcastExtension"
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear

        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.frame = picker.bounds
                button.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                button.imageView?.tintColor = .white
                button.tintColor = .white
                button.backgroundColor = .clear
            }
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {
        for subview in uiView.subviews {
            if let button = subview as? UIButton {
                button.frame = uiView.bounds
            }
        }
    }
}

#Preview {
    NavigationStack {
        StreamingView()
    }
}
