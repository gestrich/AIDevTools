import Testing
import Foundation
import Darwin
@testable import WorktreeFeature
@testable import GitSDK

@Suite("WorktreeError")
struct WorktreeErrorTests {

    @Test("listFailed includes detail in description")
    func listFailedDescription() {
        let error = WorktreeError.listFailed("some detail")
        #expect(error.errorDescription?.contains("some detail") == true)
        #expect(error.errorDescription?.contains("list") == true)
    }

    @Test("addFailed includes detail in description")
    func addFailedDescription() {
        let error = WorktreeError.addFailed("bad path")
        #expect(error.errorDescription?.contains("bad path") == true)
        #expect(error.errorDescription?.contains("add") == true)
    }

    @Test("removeFailed includes detail in description")
    func removeFailedDescription() {
        let error = WorktreeError.removeFailed("locked")
        #expect(error.errorDescription?.contains("locked") == true)
        #expect(error.errorDescription?.contains("remove") == true)
    }
}

@Suite("WorktreeStatus")
struct WorktreeStatusTests {

    @Test("proxies all properties from WorktreeInfo")
    func proxiesProperties() {
        let id = UUID()
        let info = WorktreeInfo(id: id, path: "/tmp/my-repo/worktrees/feature", branch: "feature/foo", isMain: false)
        let status = WorktreeStatus(info: info, hasUncommittedChanges: true)

        #expect(status.id == id)
        #expect(status.name == "feature")
        #expect(status.branch == "feature/foo")
        #expect(!status.isMain)
        #expect(status.path == "/tmp/my-repo/worktrees/feature")
        #expect(status.hasUncommittedChanges)
    }

    @Test("isMain is true when WorktreeInfo.isMain is true")
    func isMainForMainWorktree() {
        let info = WorktreeInfo(id: UUID(), path: "/tmp/repo", branch: "main", isMain: true)
        let status = WorktreeStatus(info: info, hasUncommittedChanges: false)

        #expect(status.isMain)
        #expect(!status.hasUncommittedChanges)
    }
}

// MARK: - Integration helpers

private func makeCommittedRepo(name: String, client: GitClient) async throws -> String {
    let rawPath = NSTemporaryDirectory() + "\(name)-\(UUID().uuidString)"
    try FileManager.default.createDirectory(atPath: rawPath, withIntermediateDirectories: true)
    // Use realpath() so paths match what git reports (e.g. /var → /private/var on macOS)
    let tempDir = rawPath.withCString { cPath -> String in
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        return Darwin.realpath(cPath, &buf).map { String(cString: $0) } ?? rawPath
    }
    try await client.execute(GitCLI.Init(), workingDirectory: tempDir)
    try await client.config(key: "user.email", value: "test@test.com", workingDirectory: tempDir)
    try await client.config(key: "user.name", value: "Test", workingDirectory: tempDir)
    try "content".write(toFile: tempDir + "/file.txt", atomically: true, encoding: .utf8)
    try await client.add(files: ["file.txt"], workingDirectory: tempDir)
    try await client.commit(message: "Initial commit", workingDirectory: tempDir)
    return tempDir
}

private func cleanup(_ path: String) {
    try? FileManager.default.removeItem(atPath: path)
}

// MARK: - ListWorktreesUseCase

@Suite("ListWorktreesUseCase")
struct ListWorktreesUseCaseTests {

    let client = GitClient()

    @Test("returns main worktree for a clean repo")
    func returnsMainWorktree() async throws {
        let repo = try await makeCommittedRepo(name: "ListUseCase", client: client)
        defer { cleanup(repo) }

        let useCase = ListWorktreesUseCase(gitClient: client)
        let statuses = try await useCase.execute(repoPath: repo)

        #expect(statuses.count == 1)
        #expect(statuses[0].isMain)
        #expect(statuses[0].path == repo)
        #expect(!statuses[0].hasUncommittedChanges)
    }

    @Test("marks worktree dirty when uncommitted changes exist")
    func marksDirtyWhenUncommittedChanges() async throws {
        let repo = try await makeCommittedRepo(name: "ListUseCaseDirty", client: client)
        defer { cleanup(repo) }

        try "modified".write(toFile: repo + "/file.txt", atomically: true, encoding: .utf8)

        let useCase = ListWorktreesUseCase(gitClient: client)
        let statuses = try await useCase.execute(repoPath: repo)

        #expect(statuses.count == 1)
        #expect(statuses[0].hasUncommittedChanges)
    }

    @Test("returns multiple worktrees when worktrees are present")
    func returnsMultipleWorktrees() async throws {
        let repo = try await makeCommittedRepo(name: "ListUseCaseMulti", client: client)
        defer { cleanup(repo) }

        let worktreePath = repo + "-wt"
        defer { cleanup(worktreePath) }

        try await client.execute(GitCLI.Branch(name: "feature-branch"), workingDirectory: repo)
        try await client.execute(
            GitCLI.Worktree.Add(destination: worktreePath, commitish: "feature-branch"),
            workingDirectory: repo
        )

        let useCase = ListWorktreesUseCase(gitClient: client)
        let statuses = try await useCase.execute(repoPath: repo)

        #expect(statuses.count == 2)
        #expect(statuses[0].isMain)
        #expect(!statuses[1].isMain)
        #expect(statuses[1].branch == "feature-branch")
    }

    @Test("throws listFailed when repo path is invalid")
    func throwsListFailedForInvalidPath() async throws {
        let useCase = ListWorktreesUseCase(gitClient: client)

        await #expect(throws: WorktreeError.self) {
            _ = try await useCase.execute(repoPath: "/nonexistent/path/\(UUID().uuidString)")
        }
    }
}

// MARK: - AddWorktreeUseCase

@Suite("AddWorktreeUseCase")
struct AddWorktreeUseCaseTests {

    let client = GitClient()

    @Test("throws addFailed when branch does not exist on origin")
    func throwsAddFailedForMissingOriginBranch() async throws {
        let repo = try await makeCommittedRepo(name: "AddUseCase", client: client)
        defer { cleanup(repo) }

        let useCase = AddWorktreeUseCase(gitClient: client, listUseCase: ListWorktreesUseCase(gitClient: client))

        await #expect(throws: WorktreeError.self) {
            try await useCase.execute(
                repoPath: repo,
                destination: repo + "-wt",
                branch: "nonexistent-branch"
            )
        }
    }
}

// MARK: - RemoveWorktreeUseCase

@Suite("RemoveWorktreeUseCase")
struct RemoveWorktreeUseCaseTests {

    let client = GitClient()

    @Test("removes worktree without force")
    func removesWorktreeWithoutForce() async throws {
        let repo = try await makeCommittedRepo(name: "RemoveUseCase", client: client)
        defer { cleanup(repo) }

        let worktreePath = repo + "-wt-remove"
        defer { cleanup(worktreePath) }

        try await client.execute(GitCLI.Branch(name: "remove-test-branch"), workingDirectory: repo)
        try await client.execute(
            GitCLI.Worktree.Add(destination: worktreePath, commitish: "remove-test-branch"),
            workingDirectory: repo
        )

        let useCase = RemoveWorktreeUseCase(gitClient: client, listUseCase: ListWorktreesUseCase(gitClient: client))
        try await useCase.execute(repoPath: repo, worktreePath: worktreePath, force: false)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
    }

    @Test("removes worktree with force")
    func removesWorktreeWithForce() async throws {
        let repo = try await makeCommittedRepo(name: "RemoveUseCaseForce", client: client)
        defer { cleanup(repo) }

        let worktreePath = repo + "-wt-force"
        defer { cleanup(worktreePath) }

        try await client.execute(GitCLI.Branch(name: "force-remove-branch"), workingDirectory: repo)
        try await client.execute(
            GitCLI.Worktree.Add(destination: worktreePath, commitish: "force-remove-branch"),
            workingDirectory: repo
        )

        let useCase = RemoveWorktreeUseCase(gitClient: client, listUseCase: ListWorktreesUseCase(gitClient: client))
        try await useCase.execute(repoPath: repo, worktreePath: worktreePath, force: true)

        #expect(!FileManager.default.fileExists(atPath: worktreePath))
    }

    @Test("throws removeFailed when worktree path does not exist")
    func throwsRemoveFailedForInvalidPath() async throws {
        let repo = try await makeCommittedRepo(name: "RemoveUseCaseInvalid", client: client)
        defer { cleanup(repo) }

        let useCase = RemoveWorktreeUseCase(gitClient: client, listUseCase: ListWorktreesUseCase(gitClient: client))

        await #expect(throws: WorktreeError.self) {
            try await useCase.execute(
                repoPath: repo,
                worktreePath: "/nonexistent/worktree/\(UUID().uuidString)",
                force: false
            )
        }
    }
}
