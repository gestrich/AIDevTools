import ClaudeChainService
import Foundation
import GitHubService
import OctokitSDK
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

        // For each branch, fetch branch HEAD → git tree → filter to claude-chain/ blobs
        var treeEntriesByBranch: [String: [GitTreeEntry]] = [:]
        treeEntriesByBranch[defaultBranch] = (try? await loadChainTreeEntries(branch: defaultBranch)) ?? []
        await withTaskGroup(of: (String, [GitTreeEntry]).self) { group in
            for branch in nonDefaultBranches {
                group.addTask {
                    let entries = (try? await self.loadChainTreeEntries(branch: branch)) ?? []
                    return (branch, entries)
                }
            }
            for await (branch, entries) in group {
                treeEntriesByBranch[branch] = entries
            }
        }

        // Build unique project → branch mapping (default branch takes priority)
        var projectBranch: [String: String] = [:]
        for branch in nonDefaultBranches {
            for name in projectNames(from: treeEntriesByBranch[branch] ?? []) {
                if projectBranch[name] == nil { projectBranch[name] = branch }
            }
        }
        for name in projectNames(from: treeEntriesByBranch[defaultBranch] ?? []) {
            projectBranch[name] = defaultBranch
        }

        return try await withThrowingTaskGroup(of: ChainProject.self) { group in
            for (name, branch) in projectBranch {
                let entries = treeEntriesByBranch[branch] ?? []
                group.addTask {
                    try await self.fetchChainProject(name: name, baseRef: branch, treeEntries: entries)
                }
            }
            var projects: [ChainProject] = []
            for try await project in group {
                projects.append(project)
            }
            return projects.sorted { $0.name < $1.name }
        }
    }

    private func loadChainTreeEntries(branch: String) async throws -> [GitTreeEntry] {
        let head = try await gitHubPRService.branchHead(branch: branch, ttl: 300)
        let allEntries = try await gitHubPRService.gitTree(treeSHA: head.treeSHA)
        return allEntries.filter {
            ($0.path.hasPrefix(ClaudeChainConstants.projectDirectoryPrefix + "/") || $0.path.hasPrefix(ClaudeChainConstants.maintenanceChainDirectory + "/")) && $0.type == "blob"
        }
    }

    private func projectNames(from entries: [GitTreeEntry]) -> [String] {
        var names: Set<String> = []
        for entry in entries {
            if let name = Project.parseSpecPathToProject(path: entry.path) {
                names.insert(name)
            }
        }
        return Array(names)
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

    private func fetchBlobContent(entry: GitTreeEntry?, path: String, ref: String) async -> String? {
        guard let entry = entry else { return nil }
        return try? await gitHubPRService.fileBlob(blobSHA: entry.sha, path: path, ref: ref)
    }

    private func fetchChainProject(name: String, baseRef: String, treeEntries: [GitTreeEntry]) async throws -> ChainProject {
        let project = Project(name: name)
        let specPath = project.specPath
        let configPath = project.configPath

        let specEntry = treeEntries.first { $0.path == specPath }
        let configEntry = treeEntries.first { $0.path == configPath }

        async let specContent = fetchBlobContent(entry: specEntry, path: specPath, ref: baseRef)
        async let configContent = fetchBlobContent(entry: configEntry, path: configPath, ref: baseRef)

        let maxOpenPRs = (await configContent).flatMap { content in
            try? ProjectConfiguration.fromYAMLString(project: project, yamlContent: content).maxOpenPRs
        }

        guard let content = await specContent, !content.isEmpty else {
            return ChainProject(
                name: name,
                specPath: specPath,
                tasks: [],
                completedTasks: 0,
                pendingTasks: 0,
                totalTasks: 0,
                baseBranch: baseRef,
                isGitHubOnly: true,
                maxOpenPRs: maxOpenPRs
            )
        }
        let spec = SpecContent(project: project, content: content)
        let tasks = spec.tasks.map { ChainTask(index: $0.index, description: $0.description, isCompleted: $0.isCompleted) }
        return ChainProject(
            name: name,
            specPath: specPath,
            tasks: tasks,
            completedTasks: spec.completedTasks,
            pendingTasks: spec.pendingTasks,
            totalTasks: spec.totalTasks,
            baseBranch: baseRef,
            maxOpenPRs: maxOpenPRs
        )
    }
}
