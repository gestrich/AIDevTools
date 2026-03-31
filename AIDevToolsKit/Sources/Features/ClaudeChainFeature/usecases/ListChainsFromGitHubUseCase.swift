import ClaudeChainService
import Foundation
import GitHubService
import PRRadarModelsService

public struct ListChainsFromGitHubUseCase {

    public struct Options: Sendable {
        public init() {}
    }

    private let gitHubPRService: any GitHubPRServiceProtocol

    public init(gitHubPRService: any GitHubPRServiceProtocol) {
        self.gitHubPRService = gitHubPRService
    }

    public func run(options: Options = Options()) async throws -> [ChainProject] {
        let defaultBranch = (try? await gitHubPRService.repository(useCache: true).defaultBranch) ?? "develop"

        // Get non-default base branches referenced by open chain PRs
        let nonDefaultBranches = try await discoverNonDefaultBranches(defaultBranch: defaultBranch)

        // List claude-chain/ directory on all known branches concurrently
        var projectsByBranch: [String: [String]] = [:]
        projectsByBranch[defaultBranch] = (try? await gitHubPRService.listDirectoryNames(path: "claude-chain", ref: defaultBranch)) ?? []
        await withTaskGroup(of: (String, [String]).self) { group in
            for branch in nonDefaultBranches {
                group.addTask {
                    let names = (try? await self.gitHubPRService.listDirectoryNames(path: "claude-chain", ref: branch)) ?? []
                    return (branch, names)
                }
            }
            for await (branch, names) in group {
                projectsByBranch[branch] = names
            }
        }

        // Build unique project → branch mapping (default branch takes priority)
        var projectBranch: [String: String] = [:]
        for branch in nonDefaultBranches {
            for name in projectsByBranch[branch] ?? [] {
                if projectBranch[name] == nil { projectBranch[name] = branch }
            }
        }
        for name in projectsByBranch[defaultBranch] ?? [] {
            projectBranch[name] = defaultBranch
        }

        return try await withThrowingTaskGroup(of: ChainProject.self) { group in
            for (name, branch) in projectBranch {
                group.addTask {
                    try await self.fetchChainProject(name: name, baseRef: branch)
                }
            }
            var projects: [ChainProject] = []
            for try await project in group {
                projects.append(project)
            }
            return projects.sorted { $0.name < $1.name }
        }
    }

    private func discoverNonDefaultBranches(defaultBranch: String) async throws -> [String] {
        let allOpen = try await gitHubPRService.listPullRequests(limit: 500, filter: PRFilter(state: .open))
        var branches: Set<String> = []
        for pr in allOpen {
            guard let headRefName = pr.headRefName,
                  let baseRefName = pr.baseRefName,
                  baseRefName != defaultBranch,
                  BranchInfo.fromBranchName(headRefName) != nil else {
                continue
            }
            branches.insert(baseRefName)
        }
        return Array(branches)
    }

    private func fetchChainProject(name: String, baseRef: String) async throws -> ChainProject {
        let specPath = "claude-chain/\(name)/spec.md"
        guard let content = try? await gitHubPRService.fileContent(path: specPath, ref: baseRef),
              !content.isEmpty else {
            return ChainProject(
                name: name,
                specPath: specPath,
                tasks: [],
                completedTasks: 0,
                pendingTasks: 0,
                totalTasks: 0,
                isGitHubOnly: true
            )
        }
        let spec = SpecContent(project: Project(name: name), content: content)
        let tasks = spec.tasks.map { ChainTask(index: $0.index, description: $0.description, isCompleted: $0.isCompleted) }
        return ChainProject(
            name: name,
            specPath: specPath,
            tasks: tasks,
            completedTasks: spec.completedTasks,
            pendingTasks: spec.pendingTasks,
            totalTasks: spec.totalTasks
        )
    }
}
