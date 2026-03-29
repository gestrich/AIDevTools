import ClaudeChainService
import Foundation
import CLISDK

/// GitHub CLI and API operations
public struct GitHubOperations: GitHubOperationsProtocol {
    
    private let githubClient: GitHubClient
    private let repositoryService: RepositoryService
    
    /// Public initializer for dependency injection
    public init(githubClient: GitHubClient, repositoryService: RepositoryService = RepositoryService()) {
        self.githubClient = githubClient
        self.repositoryService = repositoryService
    }
    
    /// Run a GitHub CLI command and return stdout
    ///
    /// - Parameter args: gh command arguments (without 'gh' prefix)
    /// - Returns: Command stdout as string
    /// - Throws: GitHubAPIError if gh command fails
    @available(*, deprecated, message: "Use specific GitHubClient methods instead")
    public static func runGhCommand(args: [String]) throws -> String {
        // Use CLIClient synchronously for backwards compatibility
        let cliClient = CLIClient()
        
        // Create a sync wrapper using RunLoop
        var result: ExecutionResult?
        var error: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            do {
                result = try await cliClient.execute(
                    command: "gh",
                    arguments: args,
                    workingDirectory: ".",
                    environment: nil,
                    printCommand: false
                )
            } catch let e {
                error = e
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = error {
            throw GitHubAPIError("GitHub CLI command failed: \(args.joined(separator: " "))\n\(error.localizedDescription)")
        }
        
        guard let result = result else {
            throw GitHubAPIError("GitHub CLI command failed: \(args.joined(separator: " "))\nNo result")
        }
        
        if result.exitCode != 0 {
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitHubAPIError("GitHub CLI command failed: \(args.joined(separator: " "))\n\(stderr.isEmpty ? result.stdout : stderr)")
        }
        
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Call GitHub REST API using gh CLI
    ///
    /// - Parameter endpoint: API endpoint path (e.g., "/repos/owner/repo/actions/runs")
    /// - Parameter method: HTTP method (GET, POST, etc.)
    /// - Returns: Parsed JSON response
    /// - Throws: GitHubAPIError if API call fails
    public func ghApiCall(endpoint: String, method: String = "GET") async throws -> [String: Any] {
        let output = try await githubClient.apiCall(endpoint: endpoint, method: method)
        
        if output.isEmpty {
            return [:]
        }
        
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw GitHubAPIError("Invalid JSON from API: \(output)")
        }
        
        return json
    }
    
    /// Static version for backwards compatibility
    @available(*, deprecated, message: "Use instance method instead")
    public static func ghApiCall(endpoint: String, method: String = "GET") throws -> [String: Any] {
        let output = try runGhCommand(args: ["api", endpoint, "--method", method])
        
        if output.isEmpty {
            return [:]
        }
        
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw GitHubAPIError("Invalid JSON from API: \(output)")
        }
        
        return json
    }
    
    /// Get list of changed files between two commits via GitHub API.
    ///
    /// Uses the GitHub Compare API: GET /repos/{owner}/{repo}/compare/{base}...{head}
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter base: Base commit SHA or branch name
    /// - Parameter head: Head commit SHA or branch name
    /// - Returns: Array of file paths that were added, modified, or removed
    /// - Throws: GitHubAPIError if API call fails
    ///
    /// Example:
    ///     // Compare two commits
    ///     let changedFiles = compareCommits(repo: "owner/repo", base: "abc123", head: "def456")
    ///     for filePath in changedFiles {
    ///         print("Changed: \(filePath)")
    ///     }
    ///     // Compare branches
    ///     let changedFiles = compareCommits(repo: "owner/repo", base: "main", head: "feature-branch")
    public static func compareCommits(repo: String, base: String, head: String) throws -> [String] {
        let endpoint = "/repos/\(repo)/compare/\(base)...\(head)"
        let response = try ghApiCall(endpoint: endpoint, method: "GET")
        
        guard let files = response["files"] as? [[String: Any]] else {
            return []
        }
        
        return files.compactMap { $0["filename"] as? String }
    }
    
    /// Get list of files changed by a pull request via GitHub API.
    ///
    /// Uses the PR Files API: GET /repos/{owner}/{repo}/pulls/{pr_number}/files
    ///
    /// This is more reliable than compare_commits for merged PRs because:
    /// - Works regardless of merge strategy (merge, squash, rebase)
    /// - Returns the actual files changed by the PR, not a branch comparison
    /// - Avoids timing issues where branches point to same commit post-merge
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prNumber: Pull request number
    /// - Returns: Array of file paths that were added, modified, or removed by the PR
    /// - Throws: GitHubAPIError if API call fails
    ///
    /// Example:
    ///     // Get files changed by PR #123
    ///     let changedFiles = getPullRequestFiles(repo: "owner/repo", prNumber: 123)
    ///     for filePath in changedFiles {
    ///         print("Changed: \(filePath)")
    ///     }
    public static func getPullRequestFiles(repo: String, prNumber: Int) throws -> [String] {
        let endpoint = "/repos/\(repo)/pulls/\(prNumber)/files"
        let output = try runGhCommand(args: ["api", endpoint, "--method", "GET"])
        
        if output.isEmpty {
            return []
        }
        
        guard let data = output.data(using: .utf8),
              let files = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            return []
        }
        
        return files.compactMap { $0["filename"] as? String }
    }
    
    /// Extract project name from changed spec files.
    ///
    /// Looks for files matching pattern: claude-chain/{project}/spec.md
    ///
    /// - Parameter changedFiles: Array of file paths from compare_commits
    /// - Returns: Project name if exactly one spec.md was changed, nil otherwise
    /// - Throws: Error if multiple different spec.md files were changed
    ///
    /// Example:
    ///     // Single project changed
    ///     let files = ["claude-chain/my-project/spec.md", "README.md"]
    ///     detectProjectFromDiff(changedFiles: files)  // returns "my-project"
    ///     // No spec files changed
    ///     let files = ["src/main.py", "README.md"]
    ///     detectProjectFromDiff(changedFiles: files)  // returns nil
    ///     // Multiple projects changed (throws error)
    ///     let files = ["claude-chain/project-a/spec.md", "claude-chain/project-b/spec.md"]
    ///     detectProjectFromDiff(changedFiles: files)  // Throws error
    public static func detectProjectFromDiff(changedFiles: [String]) throws -> String? {
        let specPattern = #"^claude-chain/([^/]+)/spec\.md$"#
        let regex = try NSRegularExpression(pattern: specPattern, options: [])
        var projects = Set<String>()
        
        for filePath in changedFiles {
            let range = NSRange(filePath.startIndex..<filePath.endIndex, in: filePath)
            if let match = regex.firstMatch(in: filePath, options: [], range: range) {
                let projectRange = Range(match.range(at: 1), in: filePath)!
                let projectName = String(filePath[projectRange])
                projects.insert(projectName)
            }
        }
        
        if projects.count == 0 {
            return nil
        } else if projects.count == 1 {
            return projects.first
        } else {
            let sortedProjects = projects.sorted()
            throw NSError(domain: "ProjectDetectionError", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Multiple projects modified in single push: \(sortedProjects). Push changes to one project at a time."
            ])
        }
    }
    
    /// Download and parse artifact JSON using GitHub API
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter artifactId: Artifact ID to download
    /// - Returns: Parsed JSON content or nil if download fails
    public static func downloadArtifactJson(repo: String, artifactId: Int) -> [String: Any]? {
        do {
            // Get artifact download URL (returns a redirect)
            let downloadEndpoint = "/repos/\(repo)/actions/artifacts/\(artifactId)/zip"
            
            // Create temp file for the zip
            let tempDir = FileManager.default.temporaryDirectory
            let tmpZipPath = tempDir.appendingPathComponent(UUID().uuidString + ".zip")
            
            defer {
                // Clean up temp file
                try? FileManager.default.removeItem(at: tmpZipPath)
            }
            
            // Download the zip file using gh api
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gh", "api", downloadEndpoint, "--method", "GET"]
            
            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()
            
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else {
                print("Warning: Failed to download artifact \(artifactId)")
                return nil
            }
            
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            try data.write(to: tmpZipPath)
            
            // Extract the ZIP file using unzip command
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzipProcess.arguments = ["-j", tmpZipPath.path, "*.json", "-d", tempDir.path]
            unzipProcess.standardOutput = Pipe()
            unzipProcess.standardError = Pipe()
            
            try unzipProcess.run()
            unzipProcess.waitUntilExit()
            
            guard unzipProcess.terminationStatus == 0 else {
                print("Warning: Failed to extract ZIP file")
                return nil
            }
            
            // Find the first JSON file in the temp directory
            let fileManager = FileManager.default
            let jsonFiles = try fileManager.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "json" }
            
            guard let jsonFile = jsonFiles.first else {
                print("Warning: No JSON file found in artifact \(artifactId)")
                return nil
            }
            
            // Parse the JSON file
            let jsonData = try Data(contentsOf: jsonFile)
            let jsonObject = try JSONSerialization.jsonObject(with: jsonData, options: [])
            
            // Clean up the extracted JSON file
            try? fileManager.removeItem(at: jsonFile)
            
            return jsonObject as? [String: Any]
            
        } catch {
            print("Warning: Failed to download/parse artifact \(artifactId): \(error)")
            return nil
        }
    }
    
    /// Ensure a GitHub label exists in the repository, create if it doesn't
    ///
    /// - Parameter label: Label name to ensure exists
    /// - Parameter gh: GitHub Actions helper instance for logging
    public static func ensureLabelExists(label: String, gh: GitHubActions) {
        do {
            // Try to create the label
            // If it already exists, gh will return an error which we'll catch
            _ = try runGhCommand(args: [
                "label", "create", label,
                "--description", "ClaudeChain automated refactoring",
                "--color", "0E8A16"  // Green color for refactor labels
            ])
            gh.writeStepSummary(text: "- Label '\(label)': ✅ Created")
            gh.setNotice(message: "Created label '\(label)'")
        } catch {
            // Check if error is because label already exists
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("already exists") {
                gh.writeStepSummary(text: "- Label '\(label)': ✅ Already exists")
            } else {
                // Re-raise if it's a different error
                gh.setError(message: "Failed to create label '\(label)': \(error)")
            }
        }
    }
    
    /// Add a label to a pull request.
    ///
    /// - Parameter repo: GitHub repository in format "owner/repo"
    /// - Parameter prNumber: PR number to add label to
    /// - Parameter label: Label name to add
    /// - Returns: True if label was added successfully, false otherwise
    public static func addLabelToPr(repo: String, prNumber: Int, label: String) -> Bool {
        do {
            _ = try runGhCommand(args: [
                "pr", "edit", String(prNumber),
                "--repo", repo,
                "--add-label", label
            ])
            return true
        } catch {
            print("Warning: Failed to add label '\(label)' to PR #\(prNumber): \(error)")
            return false
        }
    }
    
    /// Fetch file content from a specific branch via GitHub API
    ///
    /// - Parameter repo: GitHub repository in format "owner/repo"
    /// - Parameter branch: Branch name to fetch from
    /// - Parameter filePath: Path to file within repository
    /// - Returns: File content as string, or nil if file not found
    /// - Throws: GitHubAPIError if API call fails for reasons other than file not found
    public static func getFileFromBranch(repo: String, branch: String, filePath: String) throws -> String? {
        let endpoint = "/repos/\(repo)/contents/\(filePath)?ref=\(branch)"
        
        do {
            let response = try ghApiCall(endpoint: endpoint, method: "GET")
            
            // GitHub API returns content as Base64 encoded
            guard let encodedContent = response["content"] as? String else {
                return nil
            }
            
            // Remove newlines that GitHub adds to the base64 string
            let cleanedContent = encodedContent.replacingOccurrences(of: "\n", with: "")
            
            guard let data = Data(base64Encoded: cleanedContent),
                  let decodedContent = String(data: data, encoding: .utf8) else {
                throw GitHubAPIError("Failed to decode Base64 content")
            }
            
            return decodedContent
        } catch {
            // If it's a 404 (file not found), return nil
            let errorMessage = error.localizedDescription
            if errorMessage.contains("404") || errorMessage.contains("Not Found") {
                return nil
            }
            // Re-raise other errors
            throw error
        }
    }
    
    // MARK: - Protocol Implementation
    
    /// Instance method that delegates to the static method for protocol conformance
    public func getFileFromBranch(repo: String, branch: String, filePath: String) throws -> String? {
        return try GitHubOperations.getFileFromBranch(repo: repo, branch: branch, filePath: filePath)
    }
    
    /// Check if a file exists in a specific branch
    ///
    /// - Parameter repo: GitHub repository in format "owner/repo"
    /// - Parameter branch: Branch name to check
    /// - Parameter filePath: Path to file within repository
    /// - Returns: True if file exists, false otherwise
    public static func fileExistsInBranch(repo: String, branch: String, filePath: String) -> Bool {
        do {
            let content = try getFileFromBranch(repo: repo, branch: branch, filePath: filePath)
            return content != nil
        } catch {
            return false
        }
    }
    
    /// Fetch PRs with filtering, returns domain models
    ///
    /// This function provides GitHub PR querying capabilities for capacity
    /// checking and other use cases. It encapsulates all GitHub CLI command construction
    /// and JSON parsing, returning type-safe domain models.
    ///
    /// **Current Usage**:
    /// - Capacity checking (filter by assignee + state=open)
    /// - Project detection (filter by label)
    /// - Statistics collection (filter by label, configurable limit)
    ///
    /// **Design Principles**:
    /// - Parses GitHub JSON once into GitHubPullRequest domain models
    /// - Infrastructure layer owns GitHub CLI command construction
    /// - Type-safe return values for service layer consumption
    /// - Generic and reusable for any future GitHub PR query needs
    ///
    /// **Pagination Note**:
    /// The limit parameter controls the maximum number of results returned. For
    /// repositories with many PRs (>100), callers should increase the limit as needed.
    /// The GitHub CLI ('gh pr list') handles pagination internally up to the specified
    /// limit. Current usage in StatisticsService uses limit=500 which is sufficient
    /// for most ClaudeChain repositories.
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter state: "open", "closed", "merged", or "all"
    /// - Parameter label: Optional label filter (e.g., "claudechain" for ClaudeChain PRs)
    /// - Parameter assignee: Optional assignee filter (e.g., "username" for specific assignee)
    /// - Parameter since: Optional date filter (filters by created_at >= since)
    /// - Parameter limit: Max results (default 100, increase for repos with many PRs)
    /// - Returns: Array of GitHubPullRequest domain models with type-safe properties
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Check capacity
    ///     let prs = listPullRequests(repo: "owner/repo", state: "open", label: "claudechain", assignee: "alice")
    ///     print("Assignee has \(prs.count) open PRs")
    ///     
    ///     // Statistics for large repos
    ///     let allPrs = listPullRequests(repo: "owner/repo", state: "all", label: "claudechain", limit: 500)
    ///
    /// See Also:
    ///     - listMergedPullRequests(): Convenience wrapper for merged PRs
    ///     - listOpenPullRequests(): Convenience wrapper for open PRs
    ///     - GitHubPullRequest: Domain model with type-safe properties
    public static func listPullRequests(
        repo: String,
        state: String = "all",
        label: String? = nil,
        assignee: String? = nil,
        since: Date? = nil,
        limit: Int = 100
    ) throws -> [GitHubPullRequest] {
        // Build gh pr list command
        var args = [
            "pr", "list",
            "--repo", repo,
            "--state", state,
            "--limit", String(limit),
            "--json", "number,title,state,createdAt,mergedAt,assignees,labels,headRefName,baseRefName,url"
        ]
        
        // Add label filter if specified
        if let label = label {
            args.append(contentsOf: ["--label", label])
        }
        
        // Add assignee filter if specified
        if let assignee = assignee {
            args.append(contentsOf: ["--assignee", assignee])
        }
        
        // Execute command and parse JSON
        let output = try runGhCommand(args: args)
        
        guard !output.isEmpty,
              let data = output.data(using: .utf8),
              let prData = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            throw GitHubAPIError("Invalid JSON from gh pr list: \(output)")
        }
        
        // Parse into domain models
        let prs = prData.map { GitHubPullRequest.fromDict($0) }
        
        // Apply date filter if specified (gh pr list doesn't support --since)
        if let since = since {
            return prs.filter { $0.createdAt >= since }
        }
        
        return prs
    }
    
    /// Convenience function for fetching merged PRs
    ///
    /// Filters by merged state and date range (merged_at >= since).
    ///
    /// **Current Usage**: Not used in normal operations (statistics use metadata instead)
    ///
    /// **Future Usage**: Useful for:
    /// - Synchronize command: Backfill recently merged PRs into metadata
    /// - Audit reports: Verify all merged PRs have corresponding metadata entries
    /// - Historical analysis: Rebuild metadata from GitHub for specific time periods
    /// - Drift detection: Compare GitHub merge timestamps with metadata timestamps
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter since: Only include PRs merged on or after this date (filters by merged_at)
    /// - Parameter label: Optional label filter (e.g., "claudechain")
    /// - Parameter limit: Max results (default 100)
    /// - Returns: Array of merged GitHubPullRequest domain models
    ///
    /// Example:
    ///     // Future synchronize command: Backfill last 30 days
    ///     let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
    ///     let recentMerged = listMergedPullRequests(repo: "owner/repo", since: cutoff, label: "claudechain")
    ///     print("Found \(recentMerged.count) merged PRs to backfill")
    ///
    /// See Also:
    ///     - listPullRequests(): Base function with full filtering options
    ///     - docs/specs/archive/2025-12-30-adr-001-metadata-as-source-of-truth.md: ADR on metadata-first architecture
    ///     - docs/specs/archive/2025-12-30-refactor-statistics-service-architecture.md: Details on future synchronization
    public static func listMergedPullRequests(
        repo: String,
        since: Date,
        label: String? = nil,
        limit: Int = 100
    ) throws -> [GitHubPullRequest] {
        // Get merged PRs
        let prs = try listPullRequests(repo: repo, state: "merged", label: label, limit: limit)
        
        // Filter by merged_at date (not just created_at)
        // Since gh pr list doesn't support date filtering, we do it post-fetch
        return prs.filter { pr in
            guard let mergedAt = pr.mergedAt else { return false }
            return mergedAt >= since
        }
    }
    
    /// Convenience function for fetching open PRs
    ///
    /// **Current Usage**: Capacity checking (filter by assignee)
    ///
    /// **Usage Examples**:
    /// - Capacity checking: Check how many open PRs an assignee has
    /// - Stale PR detection: Find open PRs older than expected review time
    /// - Workload balancing: Cross-check assignee assignments
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter label: Optional label filter (e.g., "claudechain")
    /// - Parameter assignee: Optional assignee filter (e.g., "username")
    /// - Parameter limit: Max results (default 100)
    /// - Returns: Array of open GitHubPullRequest domain models
    ///
    /// Example:
    ///     // Check capacity
    ///     let openPrs = listOpenPullRequests(repo: "owner/repo", label: "claudechain", assignee: "alice")
    ///     print("Assignee has \(openPrs.count) open PRs")
    ///
    /// See Also:
    ///     - listPullRequests(): Base function with full filtering options
    public static func listOpenPullRequests(
        repo: String,
        label: String? = nil,
        assignee: String? = nil,
        limit: Int = 100
    ) throws -> [GitHubPullRequest] {
        return try listPullRequests(repo: repo, state: "open", label: label, assignee: assignee, limit: limit)
    }
    
    /// Convenience function for fetching PRs for a specific project
    ///
    /// Filters PRs by label and project name based on branch naming convention
    /// (claude-chain-{project_name}-{hash}).
    ///
    /// **Current Usage**: Test automation and project status queries
    ///
    /// **Usage Examples**:
    /// - Test automation: Verify workflow created PRs for a project
    /// - Project status: Check all PRs for a specific refactoring project
    /// - Cleanup: Find and close all PRs for a project
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter projectName: Project name to filter by (matches branch pattern)
    /// - Parameter label: Label filter (use DEFAULT_PR_LABEL from constants)
    /// - Parameter state: "open", "closed", "merged", or "all" (default: "all")
    /// - Parameter limit: Max results (default 100)
    /// - Returns: Array of GitHubPullRequest domain models for the project
    ///
    /// Example:
    ///     // Verify PRs created for a project
    ///     let projectPrs = listPullRequestsForProject(
    ///         repo: "owner/repo",
    ///         projectName: "my-project",
    ///         label: Constants.defaultPRLabel
    ///     )
    ///     print("Found \(projectPrs.count) PRs for project")
    ///
    /// See Also:
    ///     - listPullRequests(): Base function with full filtering options
    public static func listPullRequestsForProject(
        repo: String,
        projectName: String,
        label: String,
        state: String = "all",
        limit: Int = 100
    ) throws -> [GitHubPullRequest] {
        // Get all PRs with the label
        let allPrs = try listPullRequests(repo: repo, state: state, label: label, limit: limit)
        
        // Filter by branch naming convention: claude-chain-{project_name}-{hash}
        let branchPrefix = "claude-chain-\(projectName)-"
        return allPrs.filter { pr in
            guard let headRefName = pr.headRefName else { return false }
            return headRefName.hasPrefix(branchPrefix)
        }
    }
    
    /// Get the current repository name from git remote
    ///
    /// Determines the GitHub repository name by parsing the git remote origin URL.
    /// Works with both HTTPS and SSH remote URLs.
    ///
    /// - Parameter workingDirectory: Directory to run git commands in (default: current directory)
    /// - Returns: Repository name in "owner/repo" format
    /// - Throws: GitHubAPIError if unable to determine repository
    ///
    /// Example:
    ///     // Get current repo
    ///     let repo = getCurrentRepository()  // Returns "owner/repo"
    ///     
    ///     // Get repo from specific directory  
    ///     let repo = getCurrentRepository(workingDirectory: "/path/to/repo")
    public func getCurrentRepository(workingDirectory: String) async throws -> String {
        do {
            return try await repositoryService.getCurrentRepository(workingDirectory: workingDirectory)
        } catch {
            throw GitHubAPIError("Unable to determine repository: \(error.localizedDescription)")
        }
    }
    
    /// Static version for backwards compatibility
    @available(*, deprecated, message: "Use instance method instead")
    public static func getCurrentRepository(workingDirectory: String) throws -> String {
        // Create a sync wrapper for backwards compatibility
        let repositoryService = RepositoryService()
        var result: String?
        var error: Error?
        
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            do {
                result = try await repositoryService.getCurrentRepository(workingDirectory: workingDirectory)
            } catch let e {
                error = e
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        
        if let error = error {
            throw GitHubAPIError("Unable to determine repository: \(error.localizedDescription)")
        }
        
        guard let result = result else {
            throw GitHubAPIError("Unable to determine repository: No result")
        }
        
        return result
    }
    
    // MARK: - Workflow operations
    
    /// List workflow runs for a specific workflow and branch
    ///
    /// Fetches workflow runs from GitHub Actions API and returns them as
    /// domain models. Used for monitoring workflow execution and testing.
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter workflowName: Name of workflow file (e.g., "ci.yml")
    /// - Parameter branch: Branch name to filter runs
    /// - Parameter limit: Maximum number of runs to return (default: 10)
    /// - Returns: Array of WorkflowRun domain models, sorted by creation time (newest first)
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Get recent workflow runs for a branch
    ///     let runs = listWorkflowRuns(repo: "owner/repo", workflowName: "ci.yml", branch: "main", limit: 5)
    ///     for run in runs {
    ///         print("Run \(run.databaseID): \(run.status) - \(run.conclusion ?? "N/A")")
    ///     }
    ///     // Check latest run status
    ///     let latest = runs.first
    ///     if let latest = latest, latest.isSuccess() {
    ///         print("Latest run succeeded!")
    ///     }
    public static func listWorkflowRuns(
        repo: String,
        workflowName: String,
        branch: String,
        limit: Int = 10
    ) throws -> [WorkflowRun] {
        // Build gh run list command
        let args = [
            "run", "list",
            "--repo", repo,
            "--workflow", workflowName,
            "--branch", branch,
            "--limit", String(limit),
            "--json", "databaseId,status,conclusion,createdAt,headBranch,url"
        ]
        
        // Execute command and parse JSON
        let output = try runGhCommand(args: args)
        
        guard !output.isEmpty,
              let data = output.data(using: .utf8),
              let runData = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
            throw GitHubAPIError("Invalid JSON from gh run list: \(output)")
        }
        
        // Parse into domain models
        return runData.map { WorkflowRun.fromDict($0) }
    }
    
    /// Get the full logs for a workflow run.
    ///
    /// Fetches the complete logs for all jobs in a workflow run.
    /// Useful for debugging workflow failures or validating workflow output.
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter runId: Workflow run database ID
    /// - Returns: Complete workflow run logs as a string
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Get logs for a specific run
    ///     let logs = getWorkflowRunLogs(repo: "owner/repo", runId: 12345)
    ///     if logs.lowercased().contains("error") {
    ///         print("Found error in logs!")
    ///     }
    public static func getWorkflowRunLogs(repo: String, runId: Int) throws -> String {
        // Build gh run view command
        let args = [
            "run", "view", String(runId),
            "--repo", repo,
            "--log"
        ]
        
        // Execute command
        return try runGhCommand(args: args)
    }
    
    /// Trigger a GitHub Actions workflow with inputs
    ///
    /// Dispatches a workflow_dispatch event to trigger a workflow run.
    /// The workflow must have workflow_dispatch trigger configured.
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter workflowName: Name of workflow file (e.g., "ci.yml")
    /// - Parameter inputs: Workflow inputs as key-value pairs
    /// - Parameter ref: Git reference (branch, tag, or SHA) to run workflow on
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Trigger a workflow with inputs
    ///     triggerWorkflow(
    ///         repo: "owner/repo",
    ///         workflowName: "deploy.yml",
    ///         inputs: ["environment": "staging", "version": "v1.2.3"],
    ///         ref: "main"
    ///     )
    ///     // Trigger with no inputs
    ///     triggerWorkflow(
    ///         repo: "owner/repo",
    ///         workflowName: "test.yml",
    ///         inputs: [:],
    ///         ref: "feature-branch"
    ///     )
    public static func triggerWorkflow(
        repo: String,
        workflowName: String,
        inputs: [String: String],
        ref: String
    ) throws {
        // Build gh workflow run command
        var args = [
            "workflow", "run", workflowName,
            "--repo", repo,
            "--ref", ref
        ]
        
        // Add inputs as --field arguments
        for (key, value) in inputs {
            args.append(contentsOf: ["--field", "\(key)=\(value)"])
        }
        
        // Execute command (no output expected)
        _ = try runGhCommand(args: args)
    }
    
    // MARK: - Pull request operations (extensions)
    
    /// Get pull request for a specific branch
    ///
    /// Searches for an open PR with the given head branch name.
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter branch: Branch name to search for
    /// - Returns: GitHubPullRequest if found, nil otherwise
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Find PR for a branch
    ///     let pr = getPullRequestByBranch(repo: "owner/repo", branch: "feature-branch")
    ///     if let pr = pr {
    ///         print("Found PR #\(pr.number): \(pr.title)")
    ///     } else {
    ///         print("No PR found for branch")
    ///     }
    public static func getPullRequestByBranch(repo: String, branch: String) throws -> GitHubPullRequest? {
        // Get all open PRs and filter by branch
        let openPrs = try listOpenPullRequests(repo: repo, limit: 100)
        
        // Find PR with matching branch
        return openPrs.first { $0.headRefName == branch }
    }
    
    /// Get comments on a pull request
    ///
    /// Fetches all comments on a PR and returns them as domain models.
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prNumber: Pull request number
    /// - Returns: Array of PRComment domain models
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Get all comments on a PR
    ///     let comments = getPullRequestComments(repo: "owner/repo", prNumber: 123)
    ///     for comment in comments {
    ///         print("\(comment.author): \(comment.body)")
    ///     }
    public static func getPullRequestComments(repo: String, prNumber: Int) throws -> [PRComment] {
        // Build gh pr view command to get comments
        let args = [
            "pr", "view", String(prNumber),
            "--repo", repo,
            "--json", "comments"
        ]
        
        // Execute command and parse JSON
        let output = try runGhCommand(args: args)
        
        guard !output.isEmpty,
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
            throw GitHubAPIError("Invalid JSON from gh pr view: \(output)")
        }
        
        // Extract comments array
        guard let commentsData = json["comments"] as? [[String: Any]] else {
            return []
        }
        
        // Parse into domain models
        return commentsData.map { PRComment.fromDict($0) }
    }
    
    /// Close a pull request without merging
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prNumber: Pull request number to close
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Close a PR
    ///     closePullRequest(repo: "owner/repo", prNumber: 123)
    public static func closePullRequest(repo: String, prNumber: Int) throws {
        // Build gh pr close command
        let args = [
            "pr", "close", String(prNumber),
            "--repo", repo
        ]
        
        // Execute command
        _ = try runGhCommand(args: args)
    }
    
    /// Merge a pull request
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prNumber: Pull request number to merge
    /// - Parameter mergeMethod: Merge method to use (merge, squash, or rebase). Default: merge
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Merge a PR
    ///     mergePullRequest(repo: "owner/repo", prNumber: 123)
    ///     // Squash merge a PR
    ///     mergePullRequest(repo: "owner/repo", prNumber: 123, mergeMethod: "squash")
    public static func mergePullRequest(repo: String, prNumber: Int, mergeMethod: String = "merge") throws {
        // Build gh pr merge command
        let args = [
            "pr", "merge", String(prNumber),
            "--repo", repo,
            "--\(mergeMethod)"
        ]
        
        // Execute command
        _ = try runGhCommand(args: args)
    }
    
    // MARK: - Comment operations
    
    /// Post a comment on a pull request
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prNumber: Pull request number to comment on
    /// - Parameter body: Comment text to post
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Post a comment on PR #123
    ///     postPRComment(repo: "owner/repo", prNumber: 123, body: "Great work!")
    @available(*, deprecated, message: "Use instance method postPRCommentAsync instead")
    public static func postPRComment(repo: String, prNumber: Int, body: String) throws {
        // Use gh pr comment command
        let args = [
            "pr", "comment", String(prNumber),
            "--repo", repo,
            "--body", body
        ]
        
        // Execute command (no output expected)
        _ = try runGhCommand(args: args)
    }
    
    /// Post a comment on a pull request (async version using GitHubClient)
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prNumber: Pull request number to comment on
    /// - Parameter body: Comment text to post
    /// - Throws: GitHubAPIError if gh command fails
    public func postPRCommentAsync(repo: String, prNumber: Int, body: String) async throws {
        do {
            _ = try await githubClient.commentOnPullRequest(repo: repo, prNumber: prNumber, body: body)
        } catch {
            throw GitHubAPIError("Failed to post PR comment: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Branch operations
    
    /// Delete a remote branch
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter branch: Branch name to delete
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // Delete a remote branch
    ///     deleteBranch(repo: "owner/repo", branch: "feature-branch")
    @available(*, deprecated, message: "Use instance method deleteBranchAsync instead")
    public static func deleteBranch(repo: String, branch: String) throws {
        // Use GitHub API to delete the branch
        let endpoint = "/repos/\(repo)/git/refs/heads/\(branch)"
        
        do {
            // Use gh api with DELETE method
            _ = try runGhCommand(args: ["api", endpoint, "--method", "DELETE"])
        } catch {
            // Ignore 404 errors (branch already deleted)
            if !error.localizedDescription.contains("404") {
                throw error
            }
        }
    }
    
    /// Delete a remote branch (async version using GitHubClient)
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter branch: Branch name to delete
    /// - Throws: GitHubAPIError if gh command fails
    public func deleteBranchAsync(repo: String, branch: String) async throws {
        let endpoint = "/repos/\(repo)/git/refs/heads/\(branch)"
        
        do {
            _ = try await githubClient.apiCall(endpoint: endpoint, method: "DELETE")
        } catch {
            // Ignore 404 errors (branch already deleted)
            if !error.localizedDescription.contains("404") {
                throw GitHubAPIError("Failed to delete branch: \(error.localizedDescription)")
            }
        }
    }
    
    /// List remote branches, optionally filtered by prefix
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prefix: Optional prefix to filter branches (e.g., "claude-chain-")
    /// - Returns: Array of branch names
    /// - Throws: GitHubAPIError if gh command fails
    ///
    /// Example:
    ///     // List all branches
    ///     let branches = listBranches(repo: "owner/repo")
    ///     print("Found \(branches.count) branches")
    ///     // List branches with prefix
    ///     let testBranches = listBranches(repo: "owner/repo", prefix: "test-")
    ///     for branch in testBranches {
    ///         print(branch)
    ///     }
    @available(*, deprecated, message: "Use instance method listBranchesAsync instead")
    public static func listBranches(repo: String, prefix: String? = nil) -> [String] {
        // Use GitHub API to list branches
        let endpoint = "/repos/\(repo)/branches"
        let params = "?per_page=100"  // Get up to 100 branches per page
        
        do {
            // The branches API returns an array directly, not a dict, so use gh directly
            let output = try runGhCommand(args: ["api", endpoint + params, "--method", "GET"])
            
            guard !output.isEmpty,
                  let data = output.data(using: .utf8),
                  let branchArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                return []
            }
            
            let branches = branchArray.compactMap { $0["name"] as? String }
            
            // Filter by prefix if specified
            if let prefix = prefix {
                return branches.filter { $0.hasPrefix(prefix) }
            }
            
            return branches
            
        } catch {
            // Return empty list on error
            return []
        }
    }
    
    /// List remote branches, optionally filtered by prefix (async version using GitHubClient)
    ///
    /// - Parameter repo: GitHub repository (owner/name)
    /// - Parameter prefix: Optional prefix to filter branches (e.g., "claude-chain-")
    /// - Returns: Array of branch names
    /// - Throws: GitHubAPIError if gh command fails
    public func listBranchesAsync(repo: String, prefix: String? = nil) async throws -> [String] {
        let endpoint = "/repos/\(repo)/branches?per_page=100"
        
        do {
            let output = try await githubClient.apiCall(endpoint: endpoint, method: "GET")
            
            guard !output.isEmpty,
                  let data = output.data(using: .utf8),
                  let branchArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                return []
            }
            
            let branches = branchArray.compactMap { $0["name"] as? String }
            
            // Filter by prefix if specified
            if let prefix = prefix {
                return branches.filter { $0.hasPrefix(prefix) }
            }
            
            return branches
            
        } catch {
            throw GitHubAPIError("Failed to list branches: \(error.localizedDescription)")
        }
    }
}