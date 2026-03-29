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
        cliClient: CLIClient = CLIClient(printOutput: false),
        git: GitClient = GitClient()
    ) {
        self.client = client
        self.cliClient = cliClient
        self.git = git
    }

    public func execute(_ step: CreatePRStep, context: PipelineContext) async throws -> [any PipelineStep] {
        let workDir = context.workingDirectory ?? context.repoPath?.path ?? "."
        let branch: String
        if let contextBranch = context.gitBranch {
            branch = contextBranch
        } else {
            branch = try await git.getCurrentBranch(workingDirectory: workDir)
        }

        // Push the branch
        try await git.push(remote: "origin", branch: branch, setUpstream: true, workingDirectory: workDir)

        // Detect repo slug for gh commands
        let repoSlug = await detectRepo(workingDirectory: workDir)

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
            workingDirectory: workDir,
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

        // Get PR number
        var prViewArgs = ["pr", "view", branch, "--json", "number"]
        if !repoSlug.isEmpty {
            prViewArgs += ["--repo", repoSlug]
        }
        let prViewResult = try? await cliClient.execute(
            command: "gh",
            arguments: prViewArgs,
            workingDirectory: workDir,
            environment: nil,
            printCommand: false
        )
        let prNumber = prViewResult.flatMap { parsePRNumber(from: $0.stdout) }

        // Post PR summary comment via Claude
        if let prNumber {
            await postPRSummary(
                prNumber: prNumber,
                repoSlug: repoSlug,
                workingDirectory: workDir
            )
        }

        _ = prURL
        return []
    }

    private func postPRSummary(prNumber: String, repoSlug: String, workingDirectory: String) async {
        do {
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
            let summary = summaryResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else { return }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pr_comment_\(UUID().uuidString).md")
            try summary.write(to: tempURL, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            var commentArgs = ["pr", "comment", prNumber, "--body-file", tempURL.path]
            if !repoSlug.isEmpty {
                commentArgs += ["--repo", repoSlug]
            }
            _ = try await cliClient.execute(
                command: "gh",
                arguments: commentArgs,
                workingDirectory: workingDirectory,
                environment: nil,
                printCommand: false
            )
        } catch {
            // Non-fatal: summary posting failure doesn't abort the pipeline
        }
    }

    private func detectRepo(workingDirectory: String) async -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        guard let remoteURL = try? await git.remoteGetURL(workingDirectory: workingDirectory),
              remoteURL.contains("github.com") else {
            return ""
        }
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parsePRNumber(from jsonOutput: String) -> String? {
        guard let data = jsonOutput.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let number = json["number"] as? Int else {
            return nil
        }
        return String(number)
    }
}

private enum CreatePRError: Error {
    case commandFailed(command: String, output: String)
}
