import Foundation
import LoggingSDK
import UseCaseSDK

/// Reads all existing log entries then streams new ones as they are appended.
/// The stream never finishes on its own — cancel the enclosing `Task` to stop.
public struct StreamLogsUseCase: StreamingUseCase {
    public init() {}

    public func stream() -> AsyncThrowingStream<[LogEntry], Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let existing = try LogReaderService().readAll()
                    if !existing.isEmpty {
                        continuation.yield(existing)
                    }
                    for await newEntries in LogFileWatcher().stream() {
                        continuation.yield(newEntries)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
