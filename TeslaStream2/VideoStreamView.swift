import SwiftUI
import UniformTypeIdentifiers

struct VideoStreamView: View {

    @StateObject private var uploadManager = VideoUploadManager()
    @State private var showPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 30) {
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
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showPicker) {
            FilePicker { url in
                showPicker = false
                guard let url else { return }
                uploadManager.upload(from: url)
            }
        }
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundStyle(.white)

            Text("Stream a Video")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Pick a video from your library\nand play it on your Tesla display")
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            Button(action: { showPicker = true }) {
                Text("Choose Video")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
        }
    }

    private var uploadingView: some View {
        VStack(spacing: 24) {
            Text("Sending to Tesla\u{2026}")
                .font(.headline)
                .foregroundStyle(.white)

            ProgressView(value: uploadManager.progress)
                .progressViewStyle(LinearProgressViewStyle(tint: .white))
                .padding(.horizontal, 40)

            Text("\(Int(uploadManager.progress * 100))%")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.gray)

            Button("Cancel") { uploadManager.cancel() }
                .foregroundStyle(.gray)
                .font(.footnote)
        }
    }

    private var doneView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("Now Playing on Tesla")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text("Your video is playing in\nthe Tesla browser now")
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)

            Button(action: {
                uploadManager.reset()
                showPicker = true
            }) {
                Text("Play Another Video")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 40)
        }
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 64))
                .foregroundStyle(.red)

            Text("Upload Failed")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.white)

            Text(message)
                .font(.caption)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button(action: { uploadManager.reset() }) {
                Text("Try Again")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(14)
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
