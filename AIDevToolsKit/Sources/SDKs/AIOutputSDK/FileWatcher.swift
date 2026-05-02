#if canImport(Darwin)
import Foundation

public final class FileWatcher: Sendable {
    public let url: URL
    private let _cancelSource = CancelSource()

    public init(url: URL) {
        self.url = url
    }

    /// Cancels the DispatchSource backing `contentStream()`, finishing the stream
    /// and closing the file descriptor. Safe to call from any thread.
    ///
    /// This is necessary because `AsyncStream.onTermination` only fires when the
    /// iterator is released, which requires the Swift cooperative thread pool.
    /// Under heavy parallel CI load, the pool saturates and `onTermination` never
    /// fires, leaving the DispatchSource alive and preventing process exit.
    public func cancel() {
        _cancelSource.cancel()
    }

    /// Returns an AsyncStream that emits the file's content whenever it changes on disk.
    /// Uses DispatchSource.makeFileSystemObjectSource to watch for writes.
    /// Debounces rapid changes by 200ms to avoid flooding during multi-write operations.
    ///
    /// Call `cancel()` on the FileWatcher to stop the stream and clean up resources.
    public func contentStream() -> AsyncStream<String> {
        let url = self.url
        let cancelSource = self._cancelSource
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

            let cleanup = {
                debounce.task?.cancel()
                source.cancel()
                continuation.finish()
            }

            continuation.onTermination = { _ in
                cleanup()
            }

            // Register with the external cancel source so cancel() works from any thread.
            cancelSource.onCancel(queue: queue, handler: cleanup)

            source.resume()
        }
    }
}

/// Thread-safe cancellation token that dispatches a handler on a GCD queue.
private final class CancelSource: @unchecked Sendable {
    private var handler: (() -> Void)?
    private var queue: DispatchQueue?
    private var isCancelled = false
    private let lock = NSLock()

    func onCancel(queue: DispatchQueue, handler: @escaping () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            queue.async { handler() }
        } else {
            self.handler = handler
            self.queue = queue
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        guard !isCancelled else { lock.unlock(); return }
        isCancelled = true
        let h = handler
        let q = queue
        handler = nil
        queue = nil
        lock.unlock()
        if let h, let q { q.async { h() } }
    }
}

private final class DebounceState {
    var task: Task<Void, Never>?
}
#endif
