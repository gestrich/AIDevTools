import ArgumentParser
import ClaudeChainFeature
import ClaudeChainService
import ClaudeCLISDK
import CredentialService
import DataPathsService
import Foundation
import PRRadarCLIService

public struct StatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show chain project status and task progress"
    )

    @Option(name: .long, help: "Path to the repository containing claude-chain/")
    public var repoPath: String?

    @Argument(help: "Project name to show details for (optional, shows all if omitted)")
    public var project: String?

    @Option(name: .long, help: "GitHub token (overrides all other credential sources)")
    public var githubToken: String?

    public init() {}

    public func run() async throws {
        let path: String
        if let repoPath {
            path = repoPath
        } else if let envPath = ProcessInfo.processInfo.environment["CLAUDECHAIN_REPO_PATH"] {
            path = envPath
        } else {
            path = FileManager.default.currentDirectoryPath
        }

        let repoURL = URL(fileURLWithPath: path)
        let dataRoot = ResolveDataPathUseCase().resolve().path
        let dataPathsService = try DataPathsService(rootPath: dataRoot)

        let account: String
        if githubToken == nil {
            let accounts = try SecureSettingsService().listCredentialAccounts()
            let gitOps = GitHubServiceFactory.createGitOps()
            let remoteURL = try await gitOps.getRemoteURL(path: repoURL.path)
            let owner = GitHubAPIService.parseOwnerRepo(from: remoteURL)?.owner
            account = owner.flatMap { o in accounts.first(where: { $0 == o }) } ?? accounts.first ?? "default"
        } else {
            account = ""
        }

        let prService = try await GitHubServiceFactory.createPRService(
            repoPath: repoURL.path,
            githubAccount: account,
            explicitToken: githubToken,
            dataPathsService: dataPathsService
        )
        let chainService = ClaudeChainService(client: ClaudeProvider(), repoPath: repoURL, prService: prService)
        let result = try await chainService.listChains(source: .remote)

        for failure in result.failures {
            fputs("Warning: \(failure.localizedDescription)\n", stderr)
        }

        if result.projects.isEmpty {
            print("No chain projects found via GitHub for \(repoURL.lastPathComponent)")
            return
        }

        let detailUseCase = GetChainDetailUseCase(gitHubPRService: prService)

        if let projectName = project {
            let matched = try findProject(named: projectName, in: result.projects)
            let detail = try await detailUseCase.run(options: .init(project: matched))
            printEnrichedProjectDetail(detail)
        } else {
            var details: [ChainProjectDetail] = []
            for p in result.projects {
                do {
                    let detail = try await detailUseCase.run(options: .init(project: p))
                    details.append(detail)
                } catch {
                    fputs("Warning: failed to fetch GitHub data for '\(p.name)': \(error)\n", stderr)
                }
            }
            printEnrichedProjectList(details, allProjects: result.projects)
        }
    }

    private func findProject(named name: String, in projects: [ChainProject]) throws -> ChainProject {
        guard let matched = projects.first(where: { $0.name == name }) else {
            print("Project '\(name)' not found. Available projects:")
            for p in projects.sorted(by: { $0.name < $1.name }) {
                print("  \(p.name)")
            }
            throw ExitCode.failure
        }
        return matched
    }

    private func printEnrichedProjectDetail(_ detail: ChainProjectDetail) {
        print(detail.project.name)
        print("Progress  \(detail.project.completedTasks)/\(detail.project.totalTasks) tasks completed")
        print()
        print("Tasks")

        for enrichedTask in detail.enrichedTasks {
            let task = enrichedTask.task
            let icon = task.isCompleted ? "✓" : "○"

            if let enrichedPR = enrichedTask.enrichedPR {
                let draftPrefix = enrichedPR.isDraft ? "[DRAFT] " : ""
                let buildIndicator = buildStatusIndicator(enrichedPR.buildStatus)
                let reviewIndicator = reviewStatusIndicator(enrichedPR.reviewStatus)
                print("  \(icon) \(draftPrefix)\(task.description)  PR #\(enrichedPR.pr.number) (\(enrichedPR.ageDays)d) \(buildIndicator) \(reviewIndicator)")
            } else {
                print("  \(icon) \(task.description)")
            }
        }

        if !detail.actionItems.isEmpty {
            print()
            print("Action Items")
            for item in detail.actionItems {
                print("  ⚠️  \(item.message)")
            }
        }
    }

    private func printEnrichedProjectList(_ details: [ChainProjectDetail], allProjects: [ChainProject]) {
        let detailsByName = Dictionary(uniqueKeysWithValues: details.map { ($0.project.name, $0) })
        let sorted = allProjects.sorted { $0.name < $1.name }
        let maxNameLen = sorted.map(\.name.count).max() ?? 0

        for project in sorted {
            let padded = project.name.padding(toLength: maxNameLen, withPad: " ", startingAt: 0)
            let bar = progressBar(completed: project.completedTasks, total: project.totalTasks)
            let counts = "\(project.completedTasks)/\(project.totalTasks)"
            let actionBadge: String
            if let detail = detailsByName[project.name], !detail.actionItems.isEmpty {
                let count = detail.actionItems.count
                actionBadge = "  ⚠ \(count) action\(count == 1 ? "" : "s") needed"
            } else {
                actionBadge = ""
            }
            let kindBadgeStr = project.kind == .sweep ? "  [sweep]" : ""
            let githubOnlyNote = project.isGitHubOnly ? "  (spec on non-default branch)" : ""
            print("  \(padded)  \(bar)  \(counts)\(kindBadgeStr)\(actionBadge)\(githubOnlyNote)")
        }

        printProjectSummaryFooter(allProjects)
    }

    private func buildStatusIndicator(_ status: PRBuildStatus) -> String {
        switch status {
        case .passing: return "✅ Build"
        case .failing: return "❌ Build"
        case .pending: return "⏳ Build"
        case .conflicting: return "⚠️ Conflict"
        case .unknown: return "❓ Build"
        }
    }

    private func reviewStatusIndicator(_ status: PRReviewStatus) -> String {
        if !status.approvedBy.isEmpty {
            return "👤 \(status.approvedBy.joined(separator: ", ")) approved"
        } else if !status.pendingReviewers.isEmpty {
            return "⏳ Pending review: \(status.pendingReviewers.joined(separator: ", "))"
        } else {
            return "👤 No reviewers"
        }
    }

    private func printProjectSummaryFooter(_ projects: [ChainProject]) {
        let totalCompleted = projects.reduce(0) { $0 + $1.completedTasks }
        let totalAll = projects.reduce(0) { $0 + $1.totalTasks }
        print("\n\(projects.count) project(s), \(totalCompleted)/\(totalAll) total tasks completed")
    }

    private func progressBar(completed: Int, total: Int, width: Int = 20) -> String {
        guard total > 0 else { return "[\(String(repeating: "-", count: width))]" }
        let filled = Int(Double(completed) / Double(total) * Double(width))
        let empty = width - filled
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]"
    }
}
