import Foundation
import CLISDK

public struct GitClient: Sendable {

    private let client: CLIClient

    public init(client: CLIClient = CLIClient()) {
        self.client = client
    }

    @discardableResult
    public func fetch(remote: String = "origin", branch: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Fetch(remote: remote, branch: branch)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func createWorktree(baseBranch: String, destination: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Worktree.Add(destination: destination, commitish: "origin/\(baseBranch)")
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func removeWorktree(worktreePath: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Worktree.Remove(force: true, path: worktreePath)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func pruneWorktrees(workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Worktree.Prune()
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func add(files: [String], workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Add(files: files)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func commit(message: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Commit(message: message)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    func execute(_ command: some CLICommand, workingDirectory: String) async throws -> ExecutionResult {
        try await client.execute(
            command: GitCLI.programName,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            printCommand: false
        )
    }
}
