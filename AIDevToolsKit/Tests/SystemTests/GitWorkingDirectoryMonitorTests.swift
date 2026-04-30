import Foundation
import GitSDK
import LocalDiffService
import Testing

// System test: uses FSEventStream (via GitWorkingDirectoryMonitor) and Process().waitUntilExit().
// FSEvents are not reliable in CI sandbox environments and blocking process calls exhaust
// Swift's cooperative thread pool. Disabled in CI; run locally without the CI env var set.
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
        let stream = monitor.changes(repoPath: repo)
        let waiter = firstChange(in: stream, containing: .history)

        try await Task.sleep(nanoseconds: 300_000_000)

        try await runGit(arguments: ["commit", "--allow-empty", "-m", "Second commit"], workingDirectory: repo)

        let changes = try await awaitChange(waiter)

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
        let stream = monitor.changes(repoPath: repo)
        let waiter = firstChange(in: stream, containing: .index)

        try await Task.sleep(nanoseconds: 300_000_000)

        try write("beta\n", to: repo, path: "README.md")
        try await gitClient.addAll(workingDirectory: repo)

        let changes = try await awaitChange(waiter)

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

    private func awaitChange(_ waiter: Task<Set<GitWorkingDirectoryChange>, Error>) async throws -> Set<GitWorkingDirectoryChange> {
        try await withThrowingTaskGroup(of: Set<GitWorkingDirectoryChange>.self) { group in
            group.addTask {
                try await waiter.value
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 3_000_000_000)
                throw TestFailure("Timed out waiting for a git working directory change.")
            }

            let result = try await group.next()
            group.cancelAll()
            return try #require(result)
        }
    }

    private func runGit(arguments: [String], workingDirectory: String) async throws {
        let process = Process()
        process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardError = Pipe()
        process.standardOutput = Pipe()

        let terminationSignal = AsyncStream<Void> { continuation in
            process.terminationHandler = { _ in
                continuation.yield()
                continuation.finish()
            }
        }

        try process.run()
        for await _ in terminationSignal { break }

        if process.terminationStatus != 0 {
            throw TestFailure("git \(arguments.joined(separator: " ")) failed in \(workingDirectory)")
        }
    }
}

private struct TestFailure: Error {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
