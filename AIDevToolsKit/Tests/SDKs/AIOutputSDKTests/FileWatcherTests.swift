import Foundation
import Testing
@testable import AIOutputSDK

struct FileWatcherTests {

    // MARK: - Non-existent file

    @Test func streamFinishesImmediatelyForNonExistentFile() async {
        // Arrange
        let missingURL = URL(fileURLWithPath: "/tmp/does_not_exist_\(UUID().uuidString).txt")
        let watcher = FileWatcher(url: missingURL)
        var receivedCount = 0

        // Act
        for await _ in watcher.contentStream() {
            receivedCount += 1
        }

        // Assert
        #expect(receivedCount == 0)
    }

    // MARK: - File write detection

    @Test func emitsContentWhenFileIsWritten() async throws {
        // Arrange
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTest_\(UUID().uuidString).txt")
        try "initial".write(to: tempURL, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let watcher = FileWatcher(url: tempURL)
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
        try await Task.sleep(for: .milliseconds(400))
        task.cancel()
        await task.value

        // Assert
        #expect(receivedContent == "updated content")
    }

    // MARK: - Cancellation

    @Test func cancellationTerminatesStream() async throws {
        // Arrange
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileWatcherTest_\(UUID().uuidString).txt")
        try "content".write(to: tempURL, atomically: false, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let watcher = FileWatcher(url: tempURL)

        // Act
        let task = Task {
            for await _ in watcher.contentStream() {
                // No writes occur, so this body never runs
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        // Assert — await task.value completes, meaning the stream terminated rather than hanging
        await task.value
    }
}
