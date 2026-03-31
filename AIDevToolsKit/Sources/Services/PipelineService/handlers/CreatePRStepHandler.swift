import AIOutputSDK
import CLISDK
import Foundation
import GitSDK
import PipelineSDK

public struct CreatePRStepHandler: StepHandler {
    private let client: any AIClient
    private let cliClient: CLIClient
    private let git: GitClient

    public init(
        client: any AIClient,
        cliClient: CLIClient,
        git: GitClient
    ) {
        self.client = client
        self.cliClient = cliClient
        self.git = git
    }

    public func execute(_ step: CreatePRStep, context: PipelineContext) async throws -> [any PipelineStep] {
        let branch: String
        if let contextBranch = context.gitBranch {
            branch = contextBranch
        } else {
            branch = try await git.getCurrentBranch(workingDirectory: context.workingDirectory)
        }

        // Push the branch
        try await git.push(
            remote: "origin",
            branch: branch,
            setUpstream: true,
            force: true,
            workingDirectory: context.workingDirectory
        )

        // Detect repo slug for gh commands
        let repoSlug = try await detectRepo(workingDirectory: context.workingDirectory)

        // Create draft PR
        var prCreateArgs = [
            "pr", "create",
            "--draft",
            "--title", step.titleTemplate,
            "--body", step.bodyTemplate,
            "--head", branch,
        ]
        if let label = step.label {
            prCreateArgs += ["--label", label]
        }
        if !repoSlug.isEmpty {
            prCreateArgs += ["--repo", repoSlug]
        }
        let prURLResult = try await cliClient.execute(
            command: "gh",
            arguments: prCreateArgs,
            workingDirectory: context.workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard prURLResult.isSuccess else {
            throw CreatePRError.commandFailed(
                command: "gh \(prCreateArgs.joined(separator: " "))",
                output: prURLResult.errorOutput
            )
        }
        let prURL = prURLResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Validate PR URL is not empty
        guard !prURL.isEmpty else {
            throw CreatePRError.commandFailed(
                command: "gh \(prCreateArgs.joined(separator: " "))",
                output: "Empty PR URL returned"
            )
        }

        // Get PR number
        var prViewArgs = ["pr", "view", branch, "--json", "number"]
        if !repoSlug.isEmpty {
            prViewArgs += ["--repo", repoSlug]
        }
        let prViewResult = try await cliClient.execute(
            command: "gh",
            arguments: prViewArgs,
            workingDirectory: context.workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard prViewResult.isSuccess else {
            throw CreatePRError.commandFailed(
                command: "gh \(prViewArgs.joined(separator: " "))",
                output: prViewResult.errorOutput
            )
        }
        let prNumber = try parsePRNumber(from: prViewResult.stdout)

        // Post PR summary comment via Claude
        try await postPRSummary(
            prNumber: prNumber,
            repoSlug: repoSlug,
            workingDirectory: context.workingDirectory
        )

        return []
    }

    private func postPRSummary(prNumber: String, repoSlug: String, workingDirectory: String) async throws {
        let summaryPrompt = """
        You are reviewing a pull request. Analyze the changes made by running \
        `git diff HEAD~1...HEAD` and write a concise markdown summary of what was changed \
        and why. Output ONLY the markdown summary text.
        """
        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: workingDirectory
        )
        let summaryResult = try await client.run(prompt: summaryPrompt, options: options, onOutput: nil)
        guard summaryResult.exitCode == 0 else {
            throw CreatePRError.commandFailed(
                command: "AI summary generation",
                output: summaryResult.stderr
            )
        }
        
        let summary = summaryResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { 
            throw CreatePRError.commandFailed(
                command: "AI summary generation", 
                output: "Empty summary generated"
            )
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("pr_comment_\(UUID().uuidString).md")
        try summary.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        var commentArgs = ["pr", "comment", prNumber, "--body-file", tempURL.path]
        if !repoSlug.isEmpty {
            commentArgs += ["--repo", repoSlug]
        }
        let commentResult = try await cliClient.execute(
            command: "gh",
            arguments: commentArgs,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard commentResult.isSuccess else {
            throw CreatePRError.commandFailed(
                command: "gh \(commentArgs.joined(separator: " "))",
                output: commentResult.errorOutput
            )
        }
    }

    private func detectRepo(workingDirectory: String) async throws -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        let remoteURL = try await git.remoteGetURL(workingDirectory: workingDirectory)
        guard remoteURL.contains("github.com") else {
            throw CreatePRError.commandFailed(
                command: "repo detection",
                output: "Remote URL does not contain github.com: \(remoteURL)"
            )
        }
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsePRNumber(from jsonOutput: String) throws -> String {
        guard let data = jsonOutput.data(using: .utf8) else {
            throw CreatePRError.commandFailed(
                command: "JSON parsing",
                output: "Failed to encode JSON output as UTF-8"
            )
        }
        let response = try JSONDecoder().decode(PRViewResponse.self, from: data)
        return String(response.number)
    }
}
