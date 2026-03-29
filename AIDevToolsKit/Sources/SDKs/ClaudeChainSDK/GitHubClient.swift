import Foundation
import CLISDK

public struct GitHubClient: Sendable {

    private let client: CLIClient
    private let environment: [String: String]?
    private let workingDirectory: String

    public init(client: CLIClient = CLIClient(), environment: [String: String]? = nil, workingDirectory: String) {
        self.client = client
        self.environment = environment
        self.workingDirectory = workingDirectory
    }

    // MARK: - API Operations

    /// Call GitHub REST API using gh CLI
    ///
    /// - Parameter endpoint: API endpoint path (e.g., "/repos/owner/repo/actions/runs")
    /// - Parameter method: HTTP method (GET, POST, etc.)
    /// - Returns: Raw JSON response as string
    /// - Throws: CLIClientError if API call fails
    public func apiCall(endpoint: String, method: String = "GET") async throws -> String {
        let command = GitHubCLI.API(endpoint: endpoint, method: method)
        let result = try await execute(command)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Pull Request Operations

    /// List pull requests
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - state: "open", "closed", "merged", or "all"
    ///   - limit: Maximum number of results (default 100)
    ///   - label: Optional label filter
    ///   - assignee: Optional assignee filter
    ///   - json: JSON fields to return
    /// - Returns: Raw JSON response as string
    /// - Throws: CLIClientError if command fails
    public func listPullRequests(
        repo: String,
        state: String = "all",
        limit: Int = 100,
        label: String? = nil,
        assignee: String? = nil,
        json: String? = nil
    ) async throws -> String {
        let command = GitHubCLI.PR.List(
            repo: repo,
            state: state,
            limit: String(limit),
            label: label,
            assignee: assignee,
            json: json
        )
        let result = try await execute(command)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// View pull request details
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - prNumber: Pull request number
    ///   - json: JSON fields to return
    /// - Returns: Raw JSON response as string
    /// - Throws: CLIClientError if command fails
    public func viewPullRequest(
        repo: String,
        prNumber: Int,
        json: String? = nil
    ) async throws -> String {
        let command = GitHubCLI.PR.View(
            prNumber: String(prNumber),
            repo: repo,
            json: json
        )
        let result = try await execute(command)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Post a comment on a pull request
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - prNumber: Pull request number
    ///   - body: Comment text
    /// - Throws: CLIClientError if command fails
    @discardableResult
    public func commentOnPullRequest(
        repo: String,
        prNumber: Int,
        body: String
    ) async throws -> ExecutionResult {
        let command = GitHubCLI.PR.Comment(
            prNumber: String(prNumber),
            repo: repo,
            body: body
        )
        return try await execute(command)
    }

    /// Close a pull request
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - prNumber: Pull request number
    /// - Throws: CLIClientError if command fails
    @discardableResult
    public func closePullRequest(
        repo: String,
        prNumber: Int
    ) async throws -> ExecutionResult {
        let command = GitHubCLI.PR.Close(
            prNumber: String(prNumber),
            repo: repo
        )
        return try await execute(command)
    }

    /// Merge a pull request
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - prNumber: Pull request number
    ///   - mergeMethod: "merge", "squash", or "rebase"
    /// - Throws: CLIClientError if command fails
    @discardableResult
    public func mergePullRequest(
        repo: String,
        prNumber: Int,
        mergeMethod: String = "merge"
    ) async throws -> ExecutionResult {
        var command = GitHubCLI.PR.Merge(
            prNumber: String(prNumber),
            repo: repo
        )
        
        switch mergeMethod {
        case "merge":
            command.merge = true
        case "squash":
            command.squash = true
        case "rebase":
            command.rebase = true
        default:
            command.merge = true
        }
        
        return try await execute(command)
    }

    /// Add a label to a pull request
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - prNumber: Pull request number
    ///   - label: Label name to add
    /// - Throws: CLIClientError if command fails
    @discardableResult
    public func addLabelToPullRequest(
        repo: String,
        prNumber: Int,
        label: String
    ) async throws -> ExecutionResult {
        let command = GitHubCLI.PR.Edit(
            prNumber: String(prNumber),
            repo: repo,
            addLabel: label
        )
        return try await execute(command)
    }

    // MARK: - Workflow Operations

    /// List workflow runs
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - workflow: Workflow file name (e.g., "ci.yml")
    ///   - branch: Branch name filter
    ///   - limit: Maximum number of results (default 10)
    ///   - json: JSON fields to return
    /// - Returns: Raw JSON response as string
    /// - Throws: CLIClientError if command fails
    public func listWorkflowRuns(
        repo: String,
        workflow: String? = nil,
        branch: String? = nil,
        limit: Int = 10,
        json: String? = nil
    ) async throws -> String {
        let command = GitHubCLI.Run.List(
            repo: repo,
            workflow: workflow,
            branch: branch,
            limit: String(limit),
            json: json
        )
        let result = try await execute(command)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// View workflow run details or logs
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - runId: Workflow run ID
    ///   - showLogs: Whether to return logs instead of run details
    /// - Returns: Raw response as string
    /// - Throws: CLIClientError if command fails
    public func viewWorkflowRun(
        repo: String,
        runId: Int,
        showLogs: Bool = false
    ) async throws -> String {
        let command = GitHubCLI.Run.View(
            runId: String(runId),
            repo: repo,
            log: showLogs
        )
        let result = try await execute(command)
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trigger a workflow
    ///
    /// - Parameters:
    ///   - repo: GitHub repository (owner/name)
    ///   - workflow: Workflow file name (e.g., "deploy.yml")
    ///   - ref: Git reference to run on (branch, tag, or SHA)
    ///   - inputs: Workflow input parameters as key-value pairs
    /// - Throws: CLIClientError if command fails
    @discardableResult
    public func triggerWorkflow(
        repo: String,
        workflow: String,
        ref: String,
        inputs: [String: String] = [:]
    ) async throws -> ExecutionResult {
        var command = GitHubCLI.Workflow.Run(
            workflow: workflow,
            repo: repo,
            ref: ref
        )
        
        // Convert inputs to --field arguments
        command.fields = inputs.map { key, value in
            "\(key)=\(value)"
        }
        
        return try await execute(command)
    }

    // MARK: - Label Operations

    /// Create a label
    ///
    /// - Parameters:
    ///   - name: Label name
    ///   - description: Optional description
    ///   - color: Optional color (hex code without #)
    /// - Throws: CLIClientError if command fails
    @discardableResult
    public func createLabel(
        name: String,
        description: String? = nil,
        color: String? = nil
    ) async throws -> ExecutionResult {
        let command = GitHubCLI.Label.Create(
            name: name,
            description: description,
            color: color
        )
        return try await execute(command)
    }

    // MARK: - Private Helpers

    func execute(_ command: some CLICommand) async throws -> ExecutionResult {
        let result = try await client.execute(
            command: GitHubCLI.programName,
            arguments: command.commandArguments,
            workingDirectory: workingDirectory,
            environment: environment,
            printCommand: false
        )
        if result.exitCode != 0 {
            let args = command.commandArguments.joined(separator: " ")
            let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIClientError.executionFailed(
                command: "gh \(args)",
                exitCode: result.exitCode,
                output: stderr.isEmpty ? result.stdout : stderr
            )
        }
        return result
    }
}