import Foundation

public struct FileWatcher: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// Returns an AsyncStream that emits the file's content whenever it changes on disk.
    /// Uses DispatchSource.makeFileSystemObjectSource to watch for writes.
    /// Debounces rapid changes by 200ms to avoid flooding during multi-write operations.
    public func contentStream() -> AsyncStream<String> {
        let url = self.url
        return AsyncStream { continuation in
            let fileDescriptor = open(url.path, O_EVTONLY)
            guard fileDescriptor >= 0 else {
                continuation.finish()
                return
            }

            let queue = DispatchQueue(label: "FileWatcher.\(url.lastPathComponent)")
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fileDescriptor,
                eventMask: .write,
                queue: queue
            )

            let debounce = DebounceState()

            source.setEventHandler {
                debounce.task?.cancel()
                debounce.task = Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    guard !Task.isCancelled else { return }
                    if let content = try? String(contentsOf: url, encoding: .utf8) {
                        continuation.yield(content)
                    }
                }
            }

            source.setCancelHandler {
                close(fileDescriptor)
            }

            continuation.onTermination = { _ in
                debounce.task?.cancel()
                source.cancel()
            }

            source.resume()
        }
    }
}

private final class DebounceState {
    var task: Task<Void, Never>?
}
