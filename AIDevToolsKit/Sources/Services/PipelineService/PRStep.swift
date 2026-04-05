import CLISDK
import Foundation
import GitSDK
import Logging
import PipelineSDK

public struct PRStep: PipelineNode {
    public static var prNumberKey: PipelineContextKey<String> { .init("PRStep.prNumber") }
    public static var prURLKey: PipelineContextKey<String> { .init("PRStep.prURL") }

    public let baseBranch: String
    public let configuration: PRConfiguration
    public let displayName: String
    public let gitClient: GitClient
    public let id: String
    public let prTemplatePath: String?
    public let projectName: String?
    public let taskDescription: String?

    private let cliClient: CLIClient
    private let logger = Logger(label: "PRStep")

    public init(
        id: String,
        displayName: String,
        baseBranch: String,
        configuration: PRConfiguration,
        gitClient: GitClient,
        projectName: String? = nil,
        taskDescription: String? = nil,
        prTemplatePath: String? = nil,
        cliClient: CLIClient = CLIClient()
    ) {
        self.baseBranch = baseBranch
        self.cliClient = cliClient
        self.configuration = configuration
        self.displayName = displayName
        self.gitClient = gitClient
        self.id = id
        self.prTemplatePath = prTemplatePath
        self.projectName = projectName
        self.taskDescription = taskDescription
    }

    public func run(
        context: PipelineContext,
        onProgress: @escaping @Sendable (PipelineNodeProgress) -> Void
    ) async throws -> PipelineContext {
        let workingDirectory = context[PipelineContext.workingDirectoryKey] ?? ""
        logger.debug("PRStep.run: workingDirectory='\(workingDirectory)'")

        let branch = try await gitClient.getCurrentBranch(workingDirectory: workingDirectory)
        logger.debug("PRStep.run: branch='\(branch)', baseBranch='\(baseBranch)'")

        // Commit any uncommitted changes (Claude may leave changes unstaged/uncommitted)
        if let taskDescription {
            let uncommitted = try await gitClient.status(workingDirectory: workingDirectory)
            if !uncommitted.isEmpty {
                logger.debug("PRStep.run: found uncommitted changes, staging and committing")
                try await gitClient.addAll(workingDirectory: workingDirectory)
                let staged = try await gitClient.diffCachedNames(workingDirectory: workingDirectory)
                if !staged.isEmpty {
                    try await gitClient.commit(message: "Complete task: \(taskDescription)", workingDirectory: workingDirectory)
                    logger.debug("PRStep.run: committed \(staged.count) file(s)")
                } else {
                    logger.debug("PRStep.run: no staged changes after add (already committed by Claude)")
                }
            } else {
                logger.debug("PRStep.run: no uncommitted changes")
            }
        }

        try await gitClient.push(
            remote: "origin",
            branch: branch,
            setUpstream: true,
            force: true,
            workingDirectory: workingDirectory
        )

        let repoSlug = try await detectRepoSlug(workingDirectory: workingDirectory)

        if let maxOpen = configuration.maxOpenPRs, !repoSlug.isEmpty {
            let openCount = try await countOpenPRs(repoSlug: repoSlug, workingDirectory: workingDirectory)
            guard openCount < maxOpen else {
                throw PipelineError.capacityExceeded(openCount: openCount, maxOpen: maxOpen)
            }
        }

        var prCreateArgs = ["pr", "create", "--draft", "--head", branch, "--base", baseBranch]
        var tempBodyURL: URL?
        defer { tempBodyURL.flatMap { try? FileManager.default.removeItem(at: $0) } }

        if let taskDescription {
            let prefix = projectName.map { "ClaudeChain: [\($0)] " } ?? "ClaudeChain: "
            let maxTask = 80 - prefix.count
            let truncated = taskDescription.count > maxTask
                ? String(taskDescription.prefix(maxTask - 3)) + "..."
                : taskDescription
            let body: String
            if let path = prTemplatePath, let template = try? String(contentsOfFile: path) {
                body = template.replacingOccurrences(of: "{{TASK_DESCRIPTION}}", with: taskDescription)
            } else {
                body = taskDescription
            }
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
            try body.write(to: tempURL, atomically: true, encoding: .utf8)
            tempBodyURL = tempURL
            prCreateArgs += ["--title", "\(prefix)\(truncated)", "--body-file", tempURL.path]
        } else {
            prCreateArgs += ["--fill"]
        }
        if !repoSlug.isEmpty {
            prCreateArgs += ["--repo", repoSlug]
        }
        for label in configuration.labels {
            prCreateArgs += ["--label", label]
        }
        for assignee in configuration.assignees {
            prCreateArgs += ["--assignee", assignee]
        }
        for reviewer in configuration.reviewers {
            prCreateArgs += ["--reviewer", reviewer]
        }

        logger.debug("PRStep.run: creating PR with args: \(prCreateArgs.joined(separator: " "))")
        let prURL: String
        do {
            let result = try await cliClient.execute(
                command: "gh",
                arguments: prCreateArgs,
                workingDirectory: workingDirectory,
                environment: nil,
                printCommand: false
            )
            guard result.isSuccess else {
                logger.error("PRStep.run: gh pr create failed: \(result.errorOutput)")
                throw PRStepError.commandFailed(command: "gh pr create", output: result.errorOutput)
            }
            prURL = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            logger.debug("PRStep.run: PR created at \(prURL)")
        } catch let error as PRStepError {
            throw error
        } catch {
            logger.warning("PRStep.run: gh pr create threw, attempting recovery via gh pr view: \(error)")
            // Already-exists recovery
            var viewArgs = ["pr", "view", branch, "--json", "url", "--jq", ".url"]
            if !repoSlug.isEmpty { viewArgs += ["--repo", repoSlug] }
            let viewResult = try await cliClient.execute(
                command: "gh",
                arguments: viewArgs,
                workingDirectory: workingDirectory,
                environment: nil,
                printCommand: false
            )
            prURL = viewResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let prNumber = try await fetchPRNumber(branch: branch, repoSlug: repoSlug, workingDirectory: workingDirectory)

        var updated = context
        updated[Self.prURLKey] = prURL
        updated[Self.prNumberKey] = prNumber
        return updated
    }

    // MARK: - Private

    private func detectRepoSlug(workingDirectory: String) async throws -> String {
        if let repo = ProcessInfo.processInfo.environment["GITHUB_REPOSITORY"], !repo.isEmpty {
            return repo
        }
        let remoteURL = try await gitClient.remoteGetURL(workingDirectory: workingDirectory)
        return remoteURL
            .replacingOccurrences(of: "git@github.com:", with: "")
            .replacingOccurrences(of: "https://github.com/", with: "")
            .replacingOccurrences(of: ".git", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func countOpenPRs(repoSlug: String, workingDirectory: String) async throws -> Int {
        var args = ["pr", "list", "--state", "open", "--json", "number"]
        if !repoSlug.isEmpty { args += ["--repo", repoSlug] }
        let result = try await cliClient.execute(
            command: "gh",
            arguments: args,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard result.isSuccess, let data = result.stdout.data(using: .utf8) else {
            logger.warning("PRStep: failed to query open PRs for '\(repoSlug)', assuming 0")
            return 0
        }
        let items = try JSONDecoder().decode([PRListItem].self, from: data)
        return items.count
    }

    private func fetchPRNumber(branch: String, repoSlug: String, workingDirectory: String) async throws -> String {
        var args = ["pr", "view", branch, "--json", "number"]
        if !repoSlug.isEmpty { args += ["--repo", repoSlug] }
        let result = try await cliClient.execute(
            command: "gh",
            arguments: args,
            workingDirectory: workingDirectory,
            environment: nil,
            printCommand: false
        )
        guard result.isSuccess, let data = result.stdout.data(using: .utf8),
              let json = try? JSONDecoder().decode([String: Int].self, from: data),
              let number = json["number"] else {
            throw PRStepError.commandFailed(command: "gh pr view", output: result.errorOutput)
        }
        return String(number)
    }

}

private struct PRListItem: Decodable {
    let number: Int
}
