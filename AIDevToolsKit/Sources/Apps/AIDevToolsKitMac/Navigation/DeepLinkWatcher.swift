import AIOutputSDK
import Foundation

@MainActor
final class DeepLinkWatcher {

    nonisolated static let fileURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("AIDevTools/deeplink.txt")
    }()

    private let router = DeepLinkRouter()
    private var watchTask: Task<Void, Never>?

    func start() {
        guard watchTask == nil else { return }
        prepareFile(at: Self.fileURL)
        watchTask = Task {
            for await content in FileWatcher(url: Self.fileURL).contentStream() {
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, let url = URL(string: trimmed) else { continue }
                router.route(url)
            }
        }
    }

    func stop() {
        watchTask?.cancel()
        watchTask = nil
    }

    private func prepareFile(at url: URL) {
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
