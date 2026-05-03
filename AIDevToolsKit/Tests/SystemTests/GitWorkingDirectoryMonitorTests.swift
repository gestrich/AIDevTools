import Foundation
import GitSDK
import LocalDiffService
import Testing

// System test: uses FSEventStream (via GitWorkingDirectoryMonitor) and async Process helpers.
// Timeouts use GCD (not Task.sleep) to avoid cooperative thread-pool starvation in parallel CI.
@Suite("GitWorkingDirectoryMonitor")
struct GitWorkingDirectoryMonitorTests {
    private let gitClient = GitClient()

    @Test("publishes a history change after a commit advances HEAD")
    func publishesHistoryChangesForCommits() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("alpha\n", to: repo, path: "README.md")
        try await gitClient.addAll(workingDirectory: repo)
        try await gitClient.commit(message: "Initial commit", workingDirectory: repo)

        let monitor = GitWorkingDirectoryMonitor(
            debounceIntervalNanoseconds: 50_000_000,
            pollIntervalNanoseconds: 50_000_000
        )
        defer { monitor.cancel() }
        let stream = monitor.changes(repoPath: repo)
        let waiter = firstChange(in: stream, containing: .history)
        defer { waiter.cancel() }

        try await gcdSleep(seconds: 0.3)

        try await runGit(arguments: ["commit", "--allow-empty", "-m", "Second commit"], workingDirectory: repo)

        let changes = try await awaitChange(waiter, timeoutSeconds: 10)

        #expect(changes.contains(.history))
    }

    @Test("publishes an index change after files are staged")
    func publishesIndexChangesForStaging() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("alpha\n", to: repo, path: "README.md")
        try await gitClient.addAll(workingDirectory: repo)
        try await gitClient.commit(message: "Initial commit", workingDirectory: repo)

        let monitor = GitWorkingDirectoryMonitor(
            debounceIntervalNanoseconds: 50_000_000,
            pollIntervalNanoseconds: 50_000_000
        )
        defer { monitor.cancel() }
        let stream = monitor.changes(repoPath: repo)
        let waiter = firstChange(in: stream, containing: .index)
        defer { waiter.cancel() }

        try await gcdSleep(seconds: 0.3)

        try write("beta\n", to: repo, path: "README.md")
        try await gitClient.addAll(workingDirectory: repo)

        let changes = try await awaitChange(waiter, timeoutSeconds: 10)

        #expect(changes.contains(.index))
    }

    private func cleanupRepository(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeRepository() async throws -> String {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("GitWorkingDirectoryMonitorTests-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        try await runGit(arguments: ["init"], workingDirectory: path)
        _ = try await gitClient.config(key: "user.email", value: "tests@example.com", workingDirectory: path)
        _ = try await gitClient.config(key: "user.name", value: "Test User", workingDirectory: path)

        return path
    }

    private func write(_ content: String, to repoPath: String, path: String) throws {
        let fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(path)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func firstChange(
        in stream: AsyncStream<Set<GitWorkingDirectoryChange>>,
        containing expected: GitWorkingDirectoryChange? = nil
    ) -> Task<Set<GitWorkingDirectoryChange>, Error> {
        Task {
            var accumulated: Set<GitWorkingDirectoryChange> = []
            var iterator = stream.makeAsyncIterator()
            while let changes = await iterator.next() {
                accumulated.formUnion(changes)
                if let expected {
                    if accumulated.contains(expected) { return accumulated }
                } else {
                    return accumulated
                }
            }
            guard !accumulated.isEmpty else {
                throw TestFailure("Monitor stream ended before emitting a change.")
            }
            return accumulated
        }
    }

    /// Waits for the change waiter task to complete, with a GCD-based timeout
    /// that doesn't depend on the cooperative thread pool.
    private func awaitChange(
        _ waiter: Task<Set<GitWorkingDirectoryChange>, Error>,
        timeoutSeconds: Double
    ) async throws -> Set<GitWorkingDirectoryChange> {
        try await withCheckedThrowingContinuation { continuation in
            let resumed = LockedFlag()

            // GCD timeout — fires even when the cooperative pool is saturated
            let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            timer.schedule(deadline: .now() + timeoutSeconds)
            timer.setEventHandler {
                waiter.cancel()
                if resumed.setIfFirst() {
                    continuation.resume(throwing: TestFailure("Timed out after \(timeoutSeconds)s waiting for a git working directory change."))
                }
            }
            timer.resume()

            Task {
                do {
                    let result = try await waiter.value
                    timer.cancel()
                    if resumed.setIfFirst() {
                        continuation.resume(returning: result)
                    }
                } catch {
                    timer.cancel()
                    if resumed.setIfFirst() {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Sleeps using GCD instead of Task.sleep to avoid cooperative pool starvation.
    private func gcdSleep(seconds: Double) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                continuation.resume()
            }
        }
    }

    private func runGit(arguments: [String], workingDirectory: String) async throws {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardError = Pipe()
        process.standardOutput = Pipe()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = LockedFlag()

            process.terminationHandler = { proc in
                if resumed.setIfFirst() {
                    if proc.terminationStatus != 0 {
                        continuation.resume(throwing: TestFailure("git \(arguments.joined(separator: " ")) failed in \(workingDirectory)"))
                    } else {
                        continuation.resume()
                    }
                }
            }

            do {
                try process.run()
            } catch {
                if resumed.setIfFirst() {
                    continuation.resume(throwing: error)
                }
            }

            // GCD timeout for process execution
            DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
                if resumed.setIfFirst() {
                    process.terminate()
                    continuation.resume(throwing: TestFailure("git \(arguments.joined(separator: " ")) timed out after 30s"))
                }
            }
        }
    }
}

/// Thread-safe one-shot flag for ensuring a continuation is resumed exactly once.
private final class LockedFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()

    /// Returns `true` if this is the first call; `false` on subsequent calls.
    func setIfFirst() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if flag { return false }
        flag = true
        return true
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
