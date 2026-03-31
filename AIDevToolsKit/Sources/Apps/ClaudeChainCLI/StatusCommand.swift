import ArgumentParser
import ClaudeChainFeature
import ClaudeChainService
import CredentialService
import DataPathsService
import Foundation
import GitHubService
import PRRadarCLIService

public struct StatusCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Show chain project status and task progress"
    )

    @Option(name: .long, help: "Path to the repository containing claude-chain/")
    public var repoPath: String?

    @Flag(name: [.short, .long], help: "Fetch GitHub enrichment data (PR status, reviews, CI)")
    public var github: Bool = false

    @Argument(help: "Project name to show details for (optional, shows all if omitted)")
    public var project: String?

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
        let projects = try ListChainsUseCase().run(options: .init(repoPath: repoURL))

        if projects.isEmpty {
            print("No chain projects found in \(repoURL.appendingPathComponent("claude-chain").path)")
            return
        }

        if github {
            let prService = try await makeGitHubPRService(repoPath: repoURL)
            let detailUseCase = GetChainDetailUseCase(gitHubPRService: prService)

            if let projectName = project {
                guard let matched = projects.first(where: { $0.name == projectName }) else {
                    print("Project '\(projectName)' not found. Available projects:")
                    for p in projects.sorted(by: { $0.name < $1.name }) {
                        print("  \(p.name)")
                    }
                    throw ExitCode.failure
                }
                let detail = try await detailUseCase.run(options: .init(repoPath: repoURL, projectName: matched.name))
                printEnrichedProjectDetail(detail)
            } else {
                var details: [ChainProjectDetail] = []
                for p in projects {
                    do {
                        let detail = try await detailUseCase.run(options: .init(repoPath: repoURL, projectName: p.name))
                        details.append(detail)
                    } catch {
                        fputs("Warning: failed to fetch GitHub data for '\(p.name)': \(error)\n", stderr)
                    }
                }
                printEnrichedProjectList(details, allProjects: projects)
            }
        } else {
            if let projectName = project {
                guard let matched = projects.first(where: { $0.name == projectName }) else {
                    print("Project '\(projectName)' not found. Available projects:")
                    for p in projects.sorted(by: { $0.name < $1.name }) {
                        print("  \(p.name)")
                    }
                    throw ExitCode.failure
                }
                printProjectDetail(matched)
            } else {
                printProjectList(projects)
            }
        }
    }

    private func makeGitHubPRService(repoPath: URL) async throws -> any GitHubPRServiceProtocol {
        let accounts = (try? CredentialSettingsService().listCredentialAccounts()) ?? []
        let gitOps = GitHubServiceFactory.createGitOps()
        let remoteURL = try await gitOps.getRemoteURL(path: repoPath.path)
        let owner = GitHubAPIService.parseOwnerRepo(from: remoteURL)?.owner ?? ""
        let account = accounts.first(where: { $0 == owner }) ?? accounts.first ?? "default"
        let dataPathsService = try DataPathsService(rootPath: DataPathsService.appSupportDirectory)
        return try await GitHubServiceFactory.createPRService(
            repoPath: repoPath.path,
            githubAccount: account,
            dataPathsService: dataPathsService
        )
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
            print("  \(padded)  \(bar)  \(counts)\(actionBadge)")
        }

        let totalCompleted = allProjects.reduce(0) { $0 + $1.completedTasks }
        let totalAll = allProjects.reduce(0) { $0 + $1.totalTasks }
        print("\n\(allProjects.count) project(s), \(totalCompleted)/\(totalAll) total tasks completed")
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

    private func printProjectList(_ projects: [ChainProject]) {
        let sorted = projects.sorted { $0.name < $1.name }
        let maxNameLen = sorted.map(\.name.count).max() ?? 0

        for project in sorted {
            let padded = project.name.padding(toLength: maxNameLen, withPad: " ", startingAt: 0)
            let bar = progressBar(completed: project.completedTasks, total: project.totalTasks)
            let counts = "\(project.completedTasks)/\(project.totalTasks) tasks completed"
            let pending = project.pendingTasks > 0 ? " · \(project.pendingTasks) pending" : ""
            print("  \(padded)  \(bar)  \(counts)\(pending)")
        }

        let totalCompleted = projects.reduce(0) { $0 + $1.completedTasks }
        let totalAll = projects.reduce(0) { $0 + $1.totalTasks }
        print("\n\(projects.count) project(s), \(totalCompleted)/\(totalAll) total tasks completed")
    }

    private func printProjectDetail(_ project: ChainProject) {
        print(project.name)
        print("Progress  \(project.completedTasks)/\(project.totalTasks) tasks completed")
        print()
        print("Tasks")

        for task in project.tasks {
            let icon = task.isCompleted ? "✓" : "○"
            print("  \(icon) \(task.description)")
        }
    }

    private func progressBar(completed: Int, total: Int, width: Int = 20) -> String {
        guard total > 0 else { return "[\(String(repeating: "-", count: width))]" }
        let filled = Int(Double(completed) / Double(total) * Double(width))
        let empty = width - filled
        return "[\(String(repeating: "█", count: filled))\(String(repeating: "░", count: empty))]"
    }
}
