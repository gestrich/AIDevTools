import Foundation
import GitSDK
import LocalDiffService
import Testing
@testable import AIDevToolsKitMac

// System test: @MainActor suite that calls async Process helpers in makeRepository().
// Uses GCD-based process execution to avoid cooperative thread-pool starvation in parallel CI.
@MainActor
@Suite("CommitListDiffModel")
struct CommitListDiffModelTests {
    private let gitClient = GitClient()
    private let diffService = LocalDiffService()

    @Test("All plan commits selects only commits whose subjects match completed phase descriptions")
    func selectPlanCommitsMatchesCompletedPhaseMessages() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("phase one\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Complete Phase 1: Setup")
        let phaseOneHash = try await gitClient.getHeadHash(workingDirectory: repo)

        try write("phase one\nphase two\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Complete Phase 2: Validation")
        let phaseTwoHash = try await gitClient.getHeadHash(workingDirectory: repo)

        try write("phase one\nphase two\nother\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Refactor unrelated code")

        let model = CommitListDiffModel(
            diffService: diffService,
            workingDirectoryMonitor: GitWorkingDirectoryMonitor(),
            planPhaseDescriptions: ["Setup", "Validation"],
            repoPath: repo
        )

        await model.load()
        await model.selectPlanCommits()

        #expect(model.selectedEntryIDs == [
            "commit:\(phaseOneHash)",
            "commit:\(phaseTwoHash)",
        ])

        guard case .loaded(let diff) = model.diffState else {
            Issue.record("Expected a loaded diff after selecting plan commits.")
            return
        }
        #expect(diff.rawContent.contains("+phase two"))
    }

    private func cleanupRepository(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private nonisolated func makeRepository() async throws -> String {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CommitListDiffModelTests-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        try await runGit(arguments: ["init"], workingDirectory: path)
        _ = try await gitClient.config(key: "user.email", value: "tests@example.com", workingDirectory: path)
        _ = try await gitClient.config(key: "user.name", value: "Test User", workingDirectory: path)

        return path
    }

    private nonisolated func stageAndCommit(repoPath: String, message: String) async throws {
        try await gitClient.addAll(workingDirectory: repoPath)
        try await gitClient.commit(message: message, workingDirectory: repoPath)
    }

    private func write(_ content: String, to repoPath: String, path: String) throws {
        let fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(path)
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private nonisolated func runGit(arguments: [String], workingDirectory: String) async throws {
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
