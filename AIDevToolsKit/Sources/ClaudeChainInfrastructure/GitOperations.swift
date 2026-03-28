import ClaudeChainService
import Foundation

/// Git command operations
public struct GitOperations {
    
    /// Run a shell command and return the result
    ///
    /// - Parameter cmd: Command and arguments as array
    /// - Parameter check: Whether to raise exception on non-zero exit
    /// - Parameter captureOutput: Whether to capture stdout/stderr
    /// - Returns: Process result
    /// - Throws: Error if command fails and check=true
    public static func runCommand(cmd: [String], check: Bool = true, captureOutput: Bool = true) throws -> (status: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = cmd
        
        var stdout = ""
        var stderr = ""
        
        if captureOutput {
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe
            
            try process.run()
            process.waitUntilExit()
            
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            
            stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            stderr = String(data: stderrData, encoding: .utf8) ?? ""
        } else {
            try process.run()
            process.waitUntilExit()
        }
        
        if check && process.terminationStatus != 0 {
            throw NSError(domain: "CommandError", code: Int(process.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "Command failed: \(cmd.joined(separator: " "))\n\(stderr)"
            ])
        }
        
        return (status: process.terminationStatus, stdout: stdout, stderr: stderr)
    }
    
    /// Run a git command and return stdout
    ///
    /// - Parameter args: Git command arguments (without 'git' prefix)
    /// - Returns: Command stdout as string
    /// - Throws: GitError if git command fails
    public static func runGitCommand(args: [String]) throws -> String {
        do {
            let result = try runCommand(cmd: ["git"] + args)
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw GitError("Git command failed: \(args.joined(separator: " "))\n\(error.localizedDescription)")
        }
    }
    
    /// Ensure a git ref is available locally, fetching if needed.
    ///
    /// For shallow clones, specific refs may not be available. This function
    /// checks if the ref exists locally and fetches it on-demand if not.
    ///
    /// - Parameter ref: Git reference (commit SHA, branch name, etc.)
    /// - Throws: GitError if ref cannot be fetched
    public static func ensureRefAvailable(ref: String) throws {
        do {
            _ = try runGitCommand(args: ["cat-file", "-t", ref])
        } catch {
            print("Fetching ref \(String(ref.prefix(12)))...")
            _ = try runGitCommand(args: ["fetch", "--depth=1", "origin", ref])
        }
    }
    
    /// Detect added or modified files between two git references
    ///
    /// - Parameter refBefore: Git reference for the before state (e.g., commit SHA)
    /// - Parameter refAfter: Git reference for the after state (e.g., commit SHA)
    /// - Parameter pattern: File pattern to filter (e.g., "claude-chain/*/spec.md")
    /// - Returns: Array of file paths that were added or modified
    /// - Throws: GitError if git command fails
    public static func detectChangedFiles(refBefore: String, refAfter: String, pattern: String) throws -> [String] {
        try ensureRefAvailable(ref: refBefore)
        try ensureRefAvailable(ref: refAfter)
        
        let output = try runGitCommand(args: [
            "diff",
            "--name-only",
            "--diff-filter=AM",
            refBefore,
            refAfter,
            "--",
            pattern
        ])
        
        if output.isEmpty {
            return []
        }
        
        return output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    
    /// Detect deleted files between two git references
    ///
    /// - Parameter refBefore: Git reference for the before state (e.g., commit SHA)
    /// - Parameter refAfter: Git reference for the after state (e.g., commit SHA)
    /// - Parameter pattern: File pattern to filter (e.g., "claude-chain/*/spec.md")
    /// - Returns: Array of file paths that were deleted
    /// - Throws: GitError if git command fails
    public static func detectDeletedFiles(refBefore: String, refAfter: String, pattern: String) throws -> [String] {
        try ensureRefAvailable(ref: refBefore)
        try ensureRefAvailable(ref: refAfter)
        
        let output = try runGitCommand(args: [
            "diff",
            "--name-only",
            "--diff-filter=D",
            refBefore,
            refAfter,
            "--",
            pattern
        ])
        
        if output.isEmpty {
            return []
        }
        
        return output.components(separatedBy: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    
    /// Extract project name from a spec.md file path
    ///
    /// Expected path format: claude-chain/{project_name}/spec.md
    ///
    /// - Parameter path: File path to parse
    /// - Returns: Project name if path matches expected format, nil otherwise
    ///
    /// Examples:
    ///     parseSpecPathToProject("claude-chain/my-project/spec.md")  // returns "my-project"
    ///     parseSpecPathToProject("claude-chain/another/spec.md")    // returns "another" 
    ///     parseSpecPathToProject("invalid/path/spec.md")           // returns nil
    public static func parseSpecPathToProject(path: String) -> String? {
        let parts = path.components(separatedBy: "/")
        
        // Expected format: claude-chain/{project_name}/spec.md
        guard parts.count == 3,
              parts[0] == "claude-chain",
              parts[2] == "spec.md" else {
            return nil
        }
        
        return parts[1]
    }
}