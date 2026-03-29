import Foundation
import CLISDK

public struct GitClient: Sendable {

    private let client: CLIClient
    private let environment: [String: String]?

    public init(client: CLIClient = CLIClient(), environment: [String: String]? = nil) {
        self.client = client
        self.environment = environment
    }

    @discardableResult
    public func add(files: [String], workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Add(files: files)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func addAll(workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Add(all: true)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func checkout(ref: String, createBranch: Bool = false, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Checkout(createBranch: createBranch, ref: ref)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func commit(message: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Commit(message: message)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func createWorktree(baseBranch: String, destination: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Worktree.Add(destination: destination, commitish: "origin/\(baseBranch)")
        return try await execute(command, workingDirectory: workingDirectory)
    }

    public func diffCachedNames(workingDirectory: String) async throws -> [String] {
        let command = GitCLI.Diff(cached: true, nameOnly: true)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    @discardableResult
    public func fetch(remote: String = "origin", branch: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Fetch(remote: remote, branch: branch)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func pruneWorktrees(workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Worktree.Prune()
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func push(remote: String = "origin", branch: String, setUpstream: Bool = false, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Push(setUpstream: setUpstream, remote: remote, branch: branch)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    public func remoteGetURL(name: String = "origin", workingDirectory: String) async throws -> String {
        let command = GitCLI.Remote.GetURL(name: name)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @discardableResult
    public func removeWorktree(worktreePath: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Worktree.Remove(force: true, path: worktreePath)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    public func status(workingDirectory: String) async throws -> [String] {
        let command = GitCLI.Status(porcelain: true)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
    }

    func execute(_ command: some CLICommand, workingDirectory: String) async throws -> ExecutionResult {
        let result = try await client.execute(
            command: GitCLI.programName,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: false
        )
        if result.exitCode != 0 {
            let args = command.commandArguments.joined(separator: " ")
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIClientError.executionFailed(
                command: "git \(args)",
                exitCode: result.exitCode,
                output: stderr.isEmpty ? result.stdout : stderr
            )
        }
        return result
    }
}
