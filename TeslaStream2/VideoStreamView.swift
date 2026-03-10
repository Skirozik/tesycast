import SwiftUI
import UniformTypeIdentifiers

struct VideoStreamView: View {

    @Environment(\.dismiss) private var dismiss
    @StateObject private var uploadManager = VideoUploadManager()
    @State private var showPicker = false

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.06, blue: 0.14), Color.black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                switch uploadManager.state {
                case .idle:
                    idleView
                case .uploading:
                    uploadingView
                case .done:
                    doneView
                case .error(let msg):
                    errorView(msg)
                }

                Spacer()
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
        .sheet(isPresented: $showPicker) {
            FilePicker { url in
                showPicker = false
                guard let url else { return }
                uploadManager.upload(from: url)
            }
        }
        .onAppear {
            StreamManager.shared.startServer()
        }
        .onDisappear {
            StreamManager.shared.stopServer()
        }
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 32) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Color(red: 0.65, green: 0.3, blue: 1.0).opacity(0.14))
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28)
                            .stroke(Color(red: 0.65, green: 0.3, blue: 1.0).opacity(0.22), lineWidth: 1)
                    )
                Image(systemName: "film.stack")
                    .font(.system(size: 44, weight: .medium))
                    .foregroundStyle(Color(red: 0.65, green: 0.3, blue: 1.0))
            }

            VStack(spacing: 10) {
                Text("Stream a Video")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Pick a video from your library\nand play it on your Tesla display")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
            }

            Button(action: { showPicker = true }) {
                Text("Choose Video")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.88)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.white.opacity(0.12), radius: 14, y: 4)
            }
            .padding(.horizontal, 40)
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 28) {
            Text("Sending to Tesla\u{2026}")
                .font(.title3).fontWeight(.semibold)
                .foregroundStyle(.white)

            VStack(spacing: 12) {
                ProgressView(value: uploadManager.progress)
                    .progressViewStyle(LinearProgressViewStyle(tint: .white))
                    .padding(.horizontal, 40)

                Text("\(Int(uploadManager.progress * 100))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.5))
            }

            Button("Cancel") { uploadManager.cancel() }
                .foregroundStyle(Color.white.opacity(0.4))
                .font(.subheadline)
        }
    }

    private var doneView: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.14))
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(Color.green.opacity(0.22), lineWidth: 1))
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
            }

            VStack(spacing: 10) {
                Text("Video Ready")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
                Text("Open the URL below in your Tesla browser")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
            }

            // URL card
            VStack(alignment: .leading, spacing: 8) {
                Text("OPEN IN TESLA BROWSER")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.white.opacity(0.3))
                    .tracking(1.2)
                Text(StreamManager.shared.playerURL)
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

            Button(action: {
                uploadManager.reset()
                showPicker = true
            }) {
                Text("Play Another Video")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.88)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.white.opacity(0.12), radius: 14, y: 4)
            }
            .padding(.horizontal, 40)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .overlay(Circle().stroke(Color.red.opacity(0.2), lineWidth: 1))
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.red)
            }

            VStack(spacing: 10) {
                Text("Upload Failed")
                    .font(.title2).fontWeight(.bold)
                    .foregroundStyle(.white)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.42))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Button(action: { uploadManager.reset() }) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [Color.white, Color(white: 0.88)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .cornerRadius(18)
                    .shadow(color: Color.white.opacity(0.12), radius: 14, y: 4)
            }
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Files app picker

struct FilePicker: UIViewControllerRepresentable {

    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let types: [UTType] = [.movie, .video, .mpeg4Movie, .quickTimeMovie]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}

#Preview {
    NavigationStack { VideoStreamView() }
}
