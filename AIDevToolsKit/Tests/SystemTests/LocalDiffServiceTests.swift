import Foundation
import GitSDK
import LocalDiffService
import Testing

// System test: calls async Process helpers in makeRepository().
// Uses GCD-based process execution to avoid cooperative thread-pool starvation in parallel CI.
@Suite("LocalDiffService")
struct LocalDiffServiceTests {
    private let gitClient = GitClient()
    private let service = LocalDiffService()

    @Test("getUnstagedDiff parses working tree changes")
    func getUnstagedDiffParsesWorkingTreeChanges() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("alpha\n", to: repo, path: "Sources/Feature.swift")
        try await stageAndCommit(repoPath: repo, message: "Initial commit")

        try write("alpha\nbeta\n", to: repo, path: "Sources/Feature.swift")

        let unstagedDiff = try await service.getUnstagedDiff(repoPath: repo)

        #expect(unstagedDiff.changedFiles == ["Sources/Feature.swift"])
        #expect(unstagedDiff.hunks.count == 1)
    }

    @Test("getStagedDiff parses index changes")
    func getStagedDiffParsesIndexChanges() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("alpha\n", to: repo, path: "Sources/Feature.swift")
        try await stageAndCommit(repoPath: repo, message: "Initial commit")

        try write("alpha\nbeta\n", to: repo, path: "Sources/Feature.swift")

        try await gitClient.add(files: ["Sources/Feature.swift"], workingDirectory: repo)
        let stagedDiff = try await service.getStagedDiff(repoPath: repo)

        #expect(stagedDiff.changedFiles == ["Sources/Feature.swift"])
        #expect(stagedDiff.hunks.count == 1)
    }

    @Test("getDiff parses a selected commit")
    func getDiffParsesSelectedCommit() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("alpha\n", to: repo, path: "Sources/Feature.swift")
        try await stageAndCommit(repoPath: repo, message: "Initial commit")

        try write("alpha\nbeta\n", to: repo, path: "Sources/Feature.swift")
        try await stageAndCommit(repoPath: repo, message: "Add beta line")

        let secondCommitHash = try await gitClient.getHeadHash(workingDirectory: repo)
        let singleCommitDiff = try await service.getDiff(forCommit: secondCommitHash, repoPath: repo)

        #expect(singleCommitDiff.commitHash == secondCommitHash)
        #expect(singleCommitDiff.changedFiles == ["Sources/Feature.swift"])
        #expect(singleCommitDiff.hunks.count == 1)
    }

    @Test("getCombinedDiff spans commit ranges including a root commit")
    func getCombinedDiffSpansCommitRangesIncludingRootCommit() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("alpha\n", to: repo, path: "Sources/Feature.swift")
        try await stageAndCommit(repoPath: repo, message: "Initial commit")
        let rootCommitHash = try await gitClient.getHeadHash(workingDirectory: repo)

        try write("alpha\nbeta\n", to: repo, path: "Sources/Feature.swift")
        try await stageAndCommit(repoPath: repo, message: "Add beta line")
        let secondCommitHash = try await gitClient.getHeadHash(workingDirectory: repo)

        try write("alpha\nbeta\ngamma\n", to: repo, path: "Sources/Feature.swift")
        try await stageAndCommit(repoPath: repo, message: "Add gamma line")
        let thirdCommitHash = try await gitClient.getHeadHash(workingDirectory: repo)

        let combinedDiff = try await service.getCombinedDiff(
            commits: [thirdCommitHash, secondCommitHash],
            repoPath: repo
        )

        #expect(combinedDiff.commitHash == "\(secondCommitHash)^...\(thirdCommitHash)")
        #expect(combinedDiff.changedFiles == ["Sources/Feature.swift"])
        #expect(combinedDiff.rawContent.contains("+gamma"))

        let rootCombinedDiff = try await service.getCombinedDiff(
            commits: [secondCommitHash, rootCommitHash],
            repoPath: repo
        )
        #expect(rootCombinedDiff.changedFiles == ["Sources/Feature.swift"])
        #expect(rootCombinedDiff.rawContent.contains("+alpha"))
        #expect(rootCombinedDiff.rawContent.contains("+beta"))
    }

    @Test("lists only commits whose subject matches the requested pattern")
    func listsMatchingCommits() async throws {
        let repo = try await makeRepository()
        defer { cleanupRepository(repo) }

        try write("alpha\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Complete Phase 1: Setup")

        try write("beta\n", to: repo, path: "README.md")
        try await stageAndCommit(repoPath: repo, message: "Refactor git helpers")

        let matchingCommits = try await service.listCommitsMatching("Complete Phase", repoPath: repo)

        #expect(matchingCommits.count == 1)
        #expect(matchingCommits[0].subject == "Complete Phase 1: Setup")
    }

    private func cleanupRepository(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    private func makeRepository() async throws -> String {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LocalDiffServiceTests-\(UUID().uuidString)")
            .path
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)

        try await runGit(arguments: ["init"], workingDirectory: path)
        _ = try await gitClient.config(key: "user.email", value: "tests@example.com", workingDirectory: path)
        _ = try await gitClient.config(key: "user.name", value: "Test User", workingDirectory: path)
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).appendingPathComponent("Sources"),
            withIntermediateDirectories: true
        )

        return path
    }

    private func stageAndCommit(repoPath: String, message: String) async throws {
        try await gitClient.addAll(workingDirectory: repoPath)
        try await gitClient.commit(message: message, workingDirectory: repoPath)
    }

    private func write(_ content: String, to repoPath: String, path: String) throws {
        let fileURL = URL(fileURLWithPath: repoPath).appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
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
