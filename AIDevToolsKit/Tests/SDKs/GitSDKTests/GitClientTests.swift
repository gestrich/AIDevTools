import Testing
import Foundation
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

    @Test func worktreePruneArguments() {
        let command = GitCLI.Worktree.Prune()
        #expect(command.commandArguments == ["worktree", "prune"])
    }
}

// MARK: - Integration tests against temp repos

@Suite("GitClient")
struct GitClientTests {

    let client = GitClient()

    private func makeTempRepo() async throws -> String {
        let tempDir = NSTemporaryDirectory() + "GitClientTests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tempDir, withIntermediateDirectories: true)
        let result = try await client.execute(GitCLI.Init(), workingDirectory: tempDir)
        #expect(result.isSuccess)
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

        let result = try await client.commit(message: "empty", workingDirectory: repo)
        #expect(!result.isSuccess)
    }
}
