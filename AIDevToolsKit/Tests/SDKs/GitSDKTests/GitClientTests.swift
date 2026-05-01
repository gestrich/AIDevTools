import Testing
import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif
@testable import GitSDK

// MARK: - Command argument tests

@Suite("GitCLI commands")
struct GitCLICommandTests {

    @Test func fetchArguments() {
        let command = GitCLI.Fetch(remote: "origin", branch: "main")
        #expect(command.commandArguments == ["fetch", "origin", "main"])
    }

    @Test func addArguments() {
        let command = GitCLI.Add(files: ["a.txt", "b.txt"])
        #expect(command.commandArguments == ["add", "a.txt", "b.txt"])
    }

    @Test func commitArguments() {
        let command = GitCLI.Commit(message: "Initial commit")
        #expect(command.commandArguments == ["commit", "-m", "Initial commit"])
    }

    @Test func worktreeAddArguments() {
        let command = GitCLI.Worktree.Add(destination: "/tmp/wt", commitish: "origin/main")
        #expect(command.commandArguments == ["worktree", "add", "/tmp/wt", "origin/main"])
    }

    @Test func worktreeRemoveArguments() {
        let command = GitCLI.Worktree.Remove(force: true, path: "/tmp/wt")
        #expect(command.commandArguments == ["worktree", "remove", "--force", "/tmp/wt"])
    }

    @Test func worktreeRemoveWithoutForce() {
        let command = GitCLI.Worktree.Remove(path: "/tmp/wt")
        #expect(command.commandArguments == ["worktree", "remove", "/tmp/wt"])
    }

    @Test func worktreeListArguments() {
        let command = GitCLI.Worktree.List(porcelain: true)
        #expect(command.commandArguments == ["worktree", "list", "--porcelain"])
    }

    @Test func worktreePruneArguments() {
        let command = GitCLI.Worktree.Prune()
        #expect(command.commandArguments == ["worktree", "prune"])
    }
}

// MARK: - Integration tests against temp repos

// System test: calls GitClient.execute() → CLIClient.execute() → waitUntilExit().
// Fixed: now uses async terminationHandler.
@Suite("GitClient")
struct GitClientTests {

    let client = GitClient()

    private func makeTempRepo() async throws -> String {
        let rawPath = NSTemporaryDirectory() + "GitClientTests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: rawPath, withIntermediateDirectories: true)
        // Use realpath() so paths match what git reports (e.g. /var → /private/var on macOS)
        let tempDir = rawPath.withCString { cPath -> String in
            var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
            return realpath(cPath, &buf).map { String(cString: $0) } ?? rawPath
        }
        let result = try await client.execute(GitCLI.Init(), workingDirectory: tempDir)
        #expect(result.isSuccess)
        _ = try await client.config(key: "user.email", value: "test@example.com", workingDirectory: tempDir)
        _ = try await client.config(key: "user.name", value: "Test User", workingDirectory: tempDir)
        return tempDir
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    @Test func addAndCommitFiles() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        try "hello".write(toFile: repo + "/test.txt", atomically: true, encoding: .utf8)

        let addResult = try await client.add(files: ["test.txt"], workingDirectory: repo)
        #expect(addResult.isSuccess)

        let commitResult = try await client.commit(message: "Initial commit", workingDirectory: repo)
        #expect(commitResult.isSuccess)
        #expect(commitResult.stdout.contains("Initial commit"))
    }

    @Test func addMultipleFiles() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        try "a".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        try "b".write(toFile: repo + "/b.txt", atomically: true, encoding: .utf8)

        let result = try await client.add(files: ["a.txt", "b.txt"], workingDirectory: repo)
        #expect(result.isSuccess)
    }

    @Test func createAndRemoveWorktree() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        try "file".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        try await client.add(files: ["file.txt"], workingDirectory: repo)
        try await client.commit(message: "Initial commit", workingDirectory: repo)

        let worktreePath = repo + "-worktree"
        defer { cleanup(worktreePath) }

        try await client.execute(GitCLI.Branch(name: "test-branch"), workingDirectory: repo)

        let createResult = try await client.execute(
            GitCLI.Worktree.Add(destination: worktreePath, commitish: "test-branch"),
            workingDirectory: repo
        )
        #expect(createResult.isSuccess)
        #expect(FileManager.default.fileExists(atPath: worktreePath + "/file.txt"))

        let removeResult = try await client.removeWorktree(worktreePath: worktreePath, workingDirectory: repo)
        #expect(removeResult.isSuccess)
    }

    @Test func pruneSucceedsOnCleanRepo() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        let result = try await client.pruneWorktrees(workingDirectory: repo)
        #expect(result.isSuccess)
    }

    @Test func commitFailsWithNothingToCommit() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        await #expect(throws: (any Error).self) {
            try await client.commit(message: "empty", workingDirectory: repo)
        }
    }

    @Test func listWorktreesReturnsMainWorktree() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        try "file".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        try await client.add(files: ["file.txt"], workingDirectory: repo)
        try await client.commit(message: "Initial commit", workingDirectory: repo)

        let worktrees = try await client.listWorktrees(workingDirectory: repo)

        #expect(worktrees.count == 1)
        #expect(worktrees[0].isMain)
        #expect(worktrees[0].path == repo)
    }

    @Test func listWorktreesReturnsMultipleWorktrees() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        try "file".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        try await client.add(files: ["file.txt"], workingDirectory: repo)
        try await client.commit(message: "Initial commit", workingDirectory: repo)

        let worktreePath = repo + "-wt-list"
        defer { cleanup(worktreePath) }

        try await client.execute(GitCLI.Branch(name: "list-test-branch"), workingDirectory: repo)
        try await client.execute(
            GitCLI.Worktree.Add(destination: worktreePath, commitish: "list-test-branch"),
            workingDirectory: repo
        )

        let worktrees = try await client.listWorktrees(workingDirectory: repo)

        #expect(worktrees.count == 2)
        #expect(worktrees[0].isMain)
        #expect(!worktrees[1].isMain)
        #expect(worktrees[1].branch == "list-test-branch")
    }

    @Test func listWorktreesHandlesDetachedHead() async throws {
        let repo = try await makeTempRepo()
        defer { cleanup(repo) }

        try "file".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)
        try await client.add(files: ["file.txt"], workingDirectory: repo)
        try await client.commit(message: "Initial commit", workingDirectory: repo)

        let headHash = try await client.getHeadHash(workingDirectory: repo)
        try await client.checkout(ref: headHash, workingDirectory: repo)

        let worktrees = try await client.listWorktrees(workingDirectory: repo)

        #expect(worktrees.count == 1)
        #expect(worktrees[0].branch == "(detached)")
    }
}
