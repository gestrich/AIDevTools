import Foundation
import Synchronization

public struct LogFileWatcher: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = AIDevToolsLogging.defaultLogFileURL) {
        self.fileURL = fileURL
    }

    /// Streams batches of new `LogEntry` values as they are appended to the log file.
    /// The stream never finishes on its own — cancel the enclosing `Task` to stop watching.
    public func stream() -> AsyncStream<[LogEntry]> {
        let fileURL = self.fileURL
        return AsyncStream { continuation in
            let offset = Mutex<UInt64>(0)

            if let handle = try? FileHandle(forReadingFrom: fileURL) {
                let end = handle.seekToEndOfFile()
                offset.withLock { $0 = end }
                try? handle.close()
            }

            let fd = open(fileURL.path, O_EVTONLY)
            guard fd >= 0 else {
                continuation.finish()
                return
            }

            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd,
                eventMask: .write,
                queue: .global(qos: .utility)
            )

            source.setEventHandler {
                guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return }
                let size = handle.seekToEndOfFile()

                let currentOffset = offset.withLock { state -> UInt64 in
                    if size < state { state = 0 }
                    let prev = state
                    state = size
                    return prev
                }

                handle.seek(toFileOffset: currentOffset)
                let data = handle.readDataToEndOfFile()
                try? handle.close()

                guard !data.isEmpty else { return }
                let decoder = JSONDecoder()
                let entries = String(data: data, encoding: .utf8)?
                    .split(separator: "\n")
                    .compactMap { try? decoder.decode(LogEntry.self, from: Data($0.utf8)) } ?? []

                if !entries.isEmpty {
                    continuation.yield(entries)
                }
            }

            source.setCancelHandler { close(fd) }
            source.resume()

            continuation.onTermination = { _ in source.cancel() }
        }
    }
}
