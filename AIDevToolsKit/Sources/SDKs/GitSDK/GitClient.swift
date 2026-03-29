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
    public func push(remote: String = "origin", branch: String, setUpstream: Bool = false, force: Bool = false, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Push(setUpstream: setUpstream, force: force, remote: remote, branch: branch)
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

    @discardableResult
    public func config(key: String, value: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Config(key: key, value: value)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    public func catFile(type: Bool = true, object: String, workingDirectory: String) async throws -> String {
        let command = GitCLI.CatFile(type: type, object: object)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func revListCount(range: String, workingDirectory: String) async throws -> Int {
        let command = GitCLI.RevList(count: true, range: range)
        let result = try await execute(command, workingDirectory: workingDirectory)
        let countString = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let count = Int(countString) else {
            throw CLIClientError.executionFailed(
                command: "git rev-list --count \(range)", 
                exitCode: 1, 
                output: "Invalid count output: '\(countString)'"
            )
        }
        return count
    }

    @discardableResult
    public func fetchDepth(remote: String = "origin", ref: String, depth: Int = 1, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Fetch(depth: String(depth), remote: remote, branch: ref)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    @discardableResult
    public func remoteSetURL(name: String, url: String, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Remote.SetURL(name: name, url: url)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    /// Ensure a git ref is available locally, fetching if needed.
    ///
    /// For shallow clones, specific refs may not be available. This function
    /// checks if the ref exists locally and fetches it on-demand if not.
    ///
    /// - Parameter ref: Git reference (commit SHA, branch name, etc.)
    /// - Parameter workingDirectory: Working directory for git commands
    /// - Throws: Error if ref cannot be fetched
    public func ensureRefAvailable(ref: String, workingDirectory: String) async throws {
        do {
            _ = try await catFile(type: true, object: ref, workingDirectory: workingDirectory)
        } catch {
            print("Fetching ref \(String(ref.prefix(12)))...")
            _ = try await fetchDepth(remote: "origin", ref: ref, depth: 1, workingDirectory: workingDirectory)
        }
    }

    /// Get list of changed files between two git references
    ///
    /// - Parameters:
    ///   - ref1: First git reference (base)
    ///   - ref2: Second git reference (head)
    ///   - pattern: File pattern to match (e.g., "*.swift", "**/spec.md")
    ///   - diffFilters: Git diff filters for change types. Default: [.added, .modified]
    ///   - workingDirectory: Working directory for git commands
    /// - Returns: Array of file paths that match the criteria
    /// - Throws: Error if git command fails
    public func diffChangedFiles(ref1: String, ref2: String, pattern: String, diffFilters: [DiffFilter] = [.added, .modified], workingDirectory: String) async throws -> [String] {
        try await ensureRefAvailable(ref: ref1, workingDirectory: workingDirectory)
        try await ensureRefAvailable(ref: ref2, workingDirectory: workingDirectory)
        
        let command = GitCLI.Diff(
            cached: false,
            nameOnly: true,
            diffFilter: diffFilters.gitFilterString,
            ref1: ref1,
            ref2: ref2,
            pattern: pattern
        )
        let result = try await execute(command, workingDirectory: workingDirectory)
        
        guard !result.stdout.isEmpty else {
            return []
        }
        
        return result.stdout.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Get list of deleted files between two git references
    ///
    /// - Parameters:
    ///   - ref1: First git reference (base)
    ///   - ref2: Second git reference (head)  
    ///   - pattern: File pattern to match (e.g., "*.swift", "**/spec.md")
    ///   - workingDirectory: Working directory for git commands
    /// - Returns: Array of file paths that were deleted
    /// - Throws: Error if git command fails
    public func diffDeletedFiles(ref1: String, ref2: String, pattern: String, workingDirectory: String) async throws -> [String] {
        try await ensureRefAvailable(ref: ref1, workingDirectory: workingDirectory)
        try await ensureRefAvailable(ref: ref2, workingDirectory: workingDirectory)
        
        let command = GitCLI.Diff(
            cached: false,
            nameOnly: true,
            diffFilter: [DiffFilter.deleted].gitFilterString,
            ref1: ref1,
            ref2: ref2,
            pattern: pattern
        )
        let result = try await execute(command, workingDirectory: workingDirectory)
        
        guard !result.stdout.isEmpty else {
            return []
        }
        
        return result.stdout.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    /// Get the current branch name
    ///
    /// - Parameter workingDirectory: Working directory for git commands
    /// - Returns: Current branch name, or "main" as fallback
    /// - Throws: Error if git command fails
    public func getCurrentBranch(workingDirectory: String) async throws -> String {
        let command = GitCLI.RevParse(abbrevRef: true, ref: "HEAD")
        let result = try await execute(command, workingDirectory: workingDirectory)
        
        let branch = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        // "HEAD" is returned in detached HEAD state
        if !branch.isEmpty && branch != "HEAD" {
            return branch
        }
        return "main"  // fallback
    }

    // Claude Chain specific logic moved to ClaudeChainService layer

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
