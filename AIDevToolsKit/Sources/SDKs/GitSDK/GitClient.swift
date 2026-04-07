import Foundation
import CLISDK

public struct GitClient: Sendable {

    private let client: CLIClient
    private let environment: [String: String]?

    public init(client: CLIClient = CLIClient(), environment: [String: String]? = nil) {
        self.client = client
        self.environment = environment
    }

    public init(printOutput: Bool, environment: [String: String]? = nil) {
        self.client = CLIClient(printOutput: printOutput)
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
    public func checkout(ref: String, createBranch: Bool = false, forceCreate: Bool = false, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Checkout(createBranch: createBranch, forceCreateBranch: forceCreate, ref: ref)
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

    @discardableResult
    public func createWorktreeWithNewBranch(branchName: String, basedOn: String, destination: String, workingDirectory: String) async throws -> ExecutionResult {
        let result = try await client.execute(
            command: "git",
            arguments: ["worktree", "add", "-b", branchName, destination, basedOn],
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: false
        )
        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIClientError.executionFailed(
                command: "git worktree add -b \(branchName) \(destination) \(basedOn)",
                exitCode: result.exitCode,
                output: stderr.isEmpty ? result.stdout : stderr
            )
        }
        return result
    }

    public func listWorktrees(workingDirectory: String) async throws -> [WorktreeInfo] {
        let command = GitCLI.Worktree.List(porcelain: true)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return parseWorktreeList(result.stdout)
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

    public func listRemoteBranches(matching pattern: String, remote: String = "origin", workingDirectory: String) async throws -> [String] {
        let command = GitCLI.LsRemote(heads: true, remote: remote, pattern: "refs/heads/\(pattern)")
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout
            .components(separatedBy: .newlines)
            .filter { !$0.isEmpty }
            .compactMap { line in
                let parts = line.components(separatedBy: "\t")
                guard parts.count == 2 else { return nil }
                let ref = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                guard ref.hasPrefix("refs/heads/") else { return nil }
                return String(ref.dropFirst("refs/heads/".count))
            }
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
    public func removeWorktree(worktreePath: String, force: Bool = true, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Worktree.Remove(force: force, path: worktreePath)
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

    @discardableResult
    public func clean(force: Bool = true, directories: Bool = true, workingDirectory: String) async throws -> ExecutionResult {
        let command = GitCLI.Clean(force: force, directories: directories)
        return try await execute(command, workingDirectory: workingDirectory)
    }

    public func diffNoIndex(path1: String, path2: String) async throws -> String {
        let command = GitCLI.Diff(noIndex: true, ref1: path1, ref2: path2)
        let result = try await client.execute(
            command: GitCLI.programName,
            arguments: command.commandArguments,
            workingDirectory: nil,
            environment: environment,
            printCommand: false
        )
        // exit code 1 means differences found (normal for no-index), 2+ means error
        if result.exitCode > 1 {
            throw CLIClientError.executionFailed(
                command: "git diff --no-index",
                exitCode: result.exitCode,
                output: result.stderr
            )
        }
        return result.stdout
    }

    public func hasDirectoryChanges(from ref1: String, to ref2: String, path: String, workingDirectory: String) async throws -> Bool {
        let command = GitCLI.Diff(nameOnly: true, ref1: ref1, ref2: ref2, pattern: path)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return !result.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func getBlobHash(ref: String, path: String, workingDirectory: String) async throws -> String {
        let command = GitCLI.RevParse(ref: "\(ref):\(path)")
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func getFileContent(ref: String, path: String, workingDirectory: String) async throws -> String {
        let command = GitCLI.Show(spec: "\(ref):\(path)")
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout
    }

    public func getHeadHash(workingDirectory: String) async throws -> String {
        let command = GitCLI.RevParse(ref: "HEAD")
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func getMergeBase(ref1: String, ref2: String, workingDirectory: String) async throws -> String {
        let command = GitCLI.MergeBase(ref1: ref1, ref2: ref2)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func getRepoRoot(workingDirectory: String) async throws -> String {
        let command = GitCLI.RevParse(showTopLevel: true)
        let result = try await execute(command, workingDirectory: workingDirectory)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func isGitRepository(at path: String) async throws -> Bool {
        let command = GitCLI.RevParse(isInsideWorkTree: true)
        do {
            _ = try await execute(command, workingDirectory: path)
            return true
        } catch {
            return false
        }
    }

    public func isWorkingDirectoryClean(workingDirectory: String) async throws -> Bool {
        let lines = try await status(workingDirectory: workingDirectory)
        return lines.isEmpty
    }

    /// Returns the most recent commit matching `pattern` in the commit message.
    ///
    /// Returns `nil` if no matching commit exists or the command fails.
    public func logGrep(_ pattern: String, workingDirectory: String) async throws -> (hash: String, body: String)? {
        let command = GitCLI.Log(grep: pattern, maxCount: "1", pretty: "format:%H%n%B")
        do {
            let result = try await execute(command, workingDirectory: workingDirectory)
            let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let lines = trimmed.components(separatedBy: .newlines)
            guard let hash = lines.first, hash.count == 40 else { return nil }
            let body = lines.dropFirst().joined(separator: "\n")
            return (hash, body)
        } catch {
            return nil
        }
    }

    /// Returns all commits matching `pattern` in the commit message, newest first.
    ///
    /// Returns an empty array if no matching commits exist or the command fails.
    public func logGrepAll(_ pattern: String, workingDirectory: String) async throws -> [(hash: String, body: String)] {
        let command = GitCLI.Log(grep: pattern, pretty: "format:%H%x00%B%x00")
        do {
            let result = try await execute(command, workingDirectory: workingDirectory)
            guard !result.stdout.isEmpty else { return [] }
            let entries = result.stdout
                .components(separatedBy: "\0")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            var commits: [(hash: String, body: String)] = []
            var i = 0
            while i < entries.count {
                let hash = entries[i]
                guard hash.count == 40 else { i += 1; continue }
                let body = i + 1 < entries.count ? entries[i + 1] : ""
                commits.append((hash, body))
                i += 2
            }
            return commits
        } catch {
            return []
        }
    }

    private func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        let blocks = output.components(separatedBy: "\n\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return blocks.enumerated().compactMap { index, block in
            let lines = block.components(separatedBy: .newlines)
            var path: String?
            var branch = "(detached)"
            for line in lines {
                if line.hasPrefix("worktree ") {
                    path = String(line.dropFirst("worktree ".count))
                } else if line.hasPrefix("branch ") {
                    let ref = String(line.dropFirst("branch ".count))
                    branch = ref.hasPrefix("refs/heads/") ? String(ref.dropFirst("refs/heads/".count)) : ref
                } else if line == "detached" {
                    branch = "(detached)"
                }
            }
            guard let worktreePath = path else { return nil }
            return WorktreeInfo(id: UUID(), path: worktreePath, branch: branch, isMain: index == 0)
        }
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
