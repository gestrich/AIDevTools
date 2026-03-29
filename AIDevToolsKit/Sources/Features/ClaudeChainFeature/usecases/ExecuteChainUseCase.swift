import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation

public struct ExecuteChainUseCase: Sendable {

    public struct Options: Sendable {
        public let githubAccount: String?
        public let projectName: String
        public let repoPath: URL

        public init(repoPath: URL, projectName: String, githubAccount: String? = nil) {
            self.githubAccount = githubAccount
            self.projectName = projectName
            self.repoPath = repoPath
        }
    }

    public struct Result: Sendable {
        public let success: Bool
        public let message: String
        public let prURL: String?

        public init(success: Bool, message: String, prURL: String?) {
            self.success = success
            self.message = message
            self.prURL = prURL
        }
    }

    public init() {}

    public func run(options: Options) async throws -> Result {
        let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
        let project = Project(
            name: options.projectName,
            basePath: (chainDir as NSString).appendingPathComponent(options.projectName)
        )
        let repository = ProjectRepository(repo: "")

        guard let spec = try repository.loadLocalSpec(project: project) else {
            return Result(
                success: false,
                message: "No spec.md found for project \(options.projectName)",
                prURL: nil
            )
        }

        guard let task = spec.getNextAvailableTask() else {
            return Result(
                success: false,
                message: "All tasks completed for project \(options.projectName)",
                prURL: nil
            )
        }

        // Resolve GH_TOKEN from credential system when a github account is configured
        var processEnv: [String: String]?
        if let githubAccount = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: CredentialSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                var env = ProcessInfo.processInfo.environment
                env["GH_TOKEN"] = token
                processEnv = env
            }
        }

        let branchName = PRService.formatBranchName(projectName: options.projectName, taskHash: task.taskHash)

        try runProcess(
            arguments: ["git", "checkout", "-b", branchName],
            workingDirectory: options.repoPath
        )

        let claudePrompt = """
        Complete the following task from spec.md:

        Task: \(task.description)

        Instructions: Read the entire spec.md file below to understand both WHAT to do and HOW to do it. \
        Follow all guidelines and patterns specified in the document.

        --- BEGIN spec.md ---
        \(spec.content)
        --- END spec.md ---

        Now complete the task '\(task.description)' following all the details and instructions in the spec.md file above.
        """

        try runProcess(
            arguments: ["claude", "-p", claudePrompt, "--dangerously-skip-permissions"],
            workingDirectory: options.repoPath,
            environment: processEnv
        )

        let prTitle = "[\(options.projectName)] \(task.description)"
        let prBody = "Task \(task.index)/\(spec.totalTasks): \(task.description)"
        let prResult = try runProcess(
            arguments: [
                "gh", "pr", "create",
                "--title", prTitle,
                "--body", prBody,
                "--draft",
            ],
            workingDirectory: options.repoPath,
            environment: processEnv
        )

        let prURL = prResult.trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(
            success: true,
            message: "Task completed: \(task.description)",
            prURL: prURL.isEmpty ? nil : prURL
        )
    }

    @discardableResult
    private func runProcess(arguments: [String], workingDirectory: URL, environment: [String: String]? = nil) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        if let environment {
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw NSError(
                domain: "ExecuteChainUseCase",
                code: Int(process.terminationStatus),
                userInfo: [
                    NSLocalizedDescriptionKey: "Command failed: \(arguments.joined(separator: " "))\n\(stderr)",
                ]
            )
        }

        return stdout
    }
}
