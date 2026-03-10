import Foundation
import Combine

@MainActor
class VideoUploadManager: NSObject, ObservableObject {

    enum UploadState {
        case idle
        case uploading
        case done
        case error(String)
    }

    @Published var state: UploadState = .idle
    @Published var progress: Double = 0

    private var uploadTask: URLSessionUploadTask?
    private var uploadResponse: HTTPURLResponse?
    private var tempURL: URL?

    func upload(from url: URL) {
        tempURL = url
        state = .uploading
        progress = 0

        var request = URLRequest(url: URL(string: "http://127.0.0.1:8080/upload-video")!)
        request.httpMethod = "POST"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        uploadTask = session.uploadTask(with: request, fromFile: url)
        uploadTask?.resume()
    }

    func cancel() {
        uploadTask?.cancel()
        cleanup()
        state = .idle
        progress = 0
    }

    func reset() {
        cleanup()
        state = .idle
        progress = 0
    }

    private func cleanup() {
        if let url = tempURL {
            try? FileManager.default.removeItem(at: url)
            tempURL = nil
        }
    }
}

extension VideoUploadManager: URLSessionTaskDelegate, URLSessionDataDelegate {

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let p = totalBytesExpectedToSend > 0
            ? Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            : 0
        Task { @MainActor in self.progress = p }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        Task { @MainActor in self.uploadResponse = response as? HTTPURLResponse }
        completionHandler(.allow)
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        Task { @MainActor in
            if let error = error as? URLError, error.code == .cancelled { return }
            if let error = error {
                self.state = .error(error.localizedDescription)
                return
            }
            let statusCode = self.uploadResponse?.statusCode ?? 0
            if statusCode == 200 {
                self.cleanup()
                self.state = .done
            } else if statusCode == 413 {
                self.state = .error("Video too large. Please try a shorter clip.")
            } else {
                self.state = .error("Server error (\(statusCode)). Try again.")
            }
        }
    }
}
