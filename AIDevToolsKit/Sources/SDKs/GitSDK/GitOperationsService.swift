import CLISDK
import Foundation

public enum GitOperationsError: LocalizedError {
    case checkoutFailed(String)
    case diffFailed(String)
    case dirtyWorkingDirectory(String)
    case fetchFailed(String)
    case fileNotFound(String)
    case notARepository(String)

    public var errorDescription: String? {
        switch self {
        case .checkoutFailed(let detail):
            return "Git checkout failed: \(detail)"
        case .diffFailed(let detail):
            return "Git diff failed: \(detail)"
        case .dirtyWorkingDirectory(let path):
            return "Working directory is dirty: \(path)"
        case .fetchFailed(let detail):
            return "Git fetch failed: \(detail)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .notARepository(let path):
            return "Not a git repository: \(path)"
        }
    }
}

public struct GitOperationsService: Sendable {
    private let gitClient: GitClient

    public init(client: CLIClient, environment: [String: String]? = nil) {
        self.gitClient = GitClient(client: client, environment: environment)
    }

    public func checkWorkingDirectoryClean(repoPath: String) async throws {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        guard try await gitClient.isWorkingDirectoryClean(workingDirectory: repoPath) else {
            throw GitOperationsError.dirtyWorkingDirectory(
                "Cannot proceed - uncommitted changes detected. "
                + "Commit or stash your changes, then try again."
            )
        }
    }

    public func checkoutBranch(_ name: String, repoPath: String) async throws {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            try await gitClient.checkout(ref: name, workingDirectory: repoPath)
        } catch {
            throw GitOperationsError.checkoutFailed("Failed to checkout branch \(name): \(error)")
        }
    }

    public func checkoutCommit(sha: String, repoPath: String) async throws {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            try await gitClient.checkout(ref: sha, workingDirectory: repoPath)
        } catch {
            throw GitOperationsError.checkoutFailed("Failed to checkout \(sha): \(error)")
        }
    }

    public func clean(repoPath: String) async throws {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        try await gitClient.clean(force: true, directories: true, workingDirectory: repoPath)
    }

    public func fetchBranch(remote: String, branch: String, repoPath: String) async throws {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            try await gitClient.fetch(remote: remote, branch: branch, workingDirectory: repoPath)
        } catch {
            throw GitOperationsError.fetchFailed("Failed to fetch \(remote)/\(branch): \(error)")
        }
    }

    public func getBlobHash(commit: String, filePath: String, repoPath: String) async throws -> String {
        try await gitClient.getBlobHash(ref: commit, path: filePath, workingDirectory: repoPath)
    }

    public func getBranchDiff(base: String, head: String, remote: String, repoPath: String) async throws -> String {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            let command = GitCLI.Diff(ref1: "\(remote)/\(base)...\(remote)/\(head)")
            let result = try await gitClient.execute(command, workingDirectory: repoPath)
            return result.stdout
        } catch {
            throw GitOperationsError.diffFailed("Failed to compute diff: \(error)")
        }
    }

    public func getCurrentBranch(path: String) async throws -> String {
        try await gitClient.getCurrentBranch(workingDirectory: path)
    }

    public func getFileContent(commit: String, filePath: String, repoPath: String) async throws -> String {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        do {
            return try await gitClient.getFileContent(ref: commit, path: filePath, workingDirectory: repoPath)
        } catch {
            throw GitOperationsError.fileNotFound("File \(filePath) not found at \(commit)")
        }
    }

    public func getMergeBase(commit1: String, commit2: String, repoPath: String) async throws -> String {
        guard try await gitClient.isGitRepository(at: repoPath) else {
            throw GitOperationsError.notARepository("Not a git repository: \(repoPath)")
        }
        return try await gitClient.getMergeBase(ref1: commit1, ref2: commit2, workingDirectory: repoPath)
    }

    public func getRemoteURL(path: String) async throws -> String {
        try await gitClient.remoteGetURL(workingDirectory: path)
    }

    public func getRepoRoot(path: String) async throws -> String {
        try await gitClient.getRepoRoot(workingDirectory: path)
    }

    public func isGitRepository(path: String) async throws -> Bool {
        try await gitClient.isGitRepository(at: path)
    }

    public func diffNoIndex(oldText: String, newText: String, oldLabel: String, newLabel: String) async throws -> String {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let oldPath = tmpDir.appendingPathComponent("old.txt")
        let newPath = tmpDir.appendingPathComponent("new.txt")
        try oldText.write(to: oldPath, atomically: true, encoding: .utf8)
        try newText.write(to: newPath, atomically: true, encoding: .utf8)

        let raw = try await gitClient.diffNoIndex(path1: oldPath.path, path2: newPath.path)
        if raw.isEmpty { return "" }

        return Self.rewriteDiffLabels(diff: raw, oldPath: oldPath.path, oldLabel: oldLabel, newPath: newPath.path, newLabel: newLabel)
    }

    /// Rewrites absolute temp file paths in a unified diff with human-readable labels.
    public static func rewriteDiffLabels(diff: String, oldPath: String, oldLabel: String, newPath: String, newLabel: String) -> String {
        let oldRel = String(oldPath.dropFirst())
        let newRel = String(newPath.dropFirst())
        var result = diff
        result = result.replacingOccurrences(of: "a/\(oldRel)", with: "a/\(oldLabel)")
        result = result.replacingOccurrences(of: "b/\(newRel)", with: "b/\(newLabel)")
        return result
    }
}
