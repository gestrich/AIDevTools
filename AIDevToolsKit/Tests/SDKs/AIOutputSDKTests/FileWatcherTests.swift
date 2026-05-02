#if canImport(Darwin)
import Foundation
import Testing
@testable import AIOutputSDK

struct FileWatcherTests {

    // MARK: - Non-existent file

    @Test func streamFinishesImmediatelyForNonExistentFile() async {
        // Arrange
        let missingURL = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).txt")
        let watcher = FileWatcher(url: missingURL)
        defer { watcher.cancel() }
        var receivedCount = 0

        // Act
        for await _ in watcher.contentStream() {
            receivedCount += 1
        }

        // Assert
        #expect(receivedCount == 0)
    }

    // MARK: - File write detection

    @Test(.timeLimit(.minutes(1)))
    func emitsContentWhenFileIsWritten() async throws {
        // Arrange
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTest_\(UUID().uuidString).txt")
        try "initial".write(to: tempURL, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let watcher = FileWatcher(url: tempURL)
        defer { watcher.cancel() }
        var receivedContent: String?

        // Act
        let task = Task {
            for await content in watcher.contentStream() {
                receivedContent = content
                break
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        try "updated content".write(to: tempURL, atomically: false, encoding: .utf8)

        // Wait for 200ms debounce + delivery margin
        try await Task.sleep(for: .seconds(3))
        task.cancel()
        // watcher.cancel() fires via defer, cleaning up the DispatchSource on a
        // GCD queue (immune to cooperative thread-pool saturation).

        // Assert
        #expect(receivedContent == "updated content")
    }

    // MARK: - Cancellation

    @Test(.timeLimit(.minutes(1)))
    func cancellationTerminatesStream() async throws {
        // Arrange
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTest_\(UUID().uuidString).txt")
        try "content".write(to: tempURL, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let watcher = FileWatcher(url: tempURL)
        defer { watcher.cancel() }

        // Act
        let task = Task {
            for await _ in watcher.contentStream() {
                // No writes occur, so this body never runs
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        // watcher.cancel() fires via defer, cleaning up the DispatchSource on a
        // GCD queue (immune to cooperative thread-pool saturation).
    }
}
#endif
