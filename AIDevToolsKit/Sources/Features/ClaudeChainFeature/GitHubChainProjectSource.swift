import ClaudeChainService
import Foundation
import GitHubService
import OctokitSDK
import PRRadarModelsService

public struct GitHubChainProjectSource: ChainProjectSource {

    private let gitHubPRService: any GitHubPRServiceProtocol

    public init(gitHubPRService: any GitHubPRServiceProtocol) {
        self.gitHubPRService = gitHubPRService
    }

    public func listChains(useCache: Bool) async throws -> ChainListResult {
        let defaultBranch = try await gitHubPRService.repository(useCache: useCache).defaultBranch
        let nonDefaultBranches = try await discoverNonDefaultBranches(defaultBranch: defaultBranch)

        var treeEntriesByBranch: [String: [GitTreeEntry]] = [:]
        var failures: [ChainFetchFailure] = []

        do {
            treeEntriesByBranch[defaultBranch] = try await loadChainTreeEntries(branch: defaultBranch)
        } catch {
            failures.append(ChainFetchFailure(context: "Failed to load chains from '\(defaultBranch)'", underlyingError: error))
        }

        await withTaskGroup(of: (String, Result<[GitTreeEntry], Error>).self) { group in
            for branch in nonDefaultBranches {
                group.addTask {
                    do {
                        return (branch, .success(try await self.loadChainTreeEntries(branch: branch)))
                    } catch {
                        return (branch, .failure(error))
                    }
                }
            }
            for await (branch, result) in group {
                switch result {
                case .success(let entries):
                    treeEntriesByBranch[branch] = entries
                case .failure(let error):
                    failures.append(ChainFetchFailure(context: "Failed to load chains from '\(branch)'", underlyingError: error))
                }
            }
        }

        var projectBranch: [String: (branch: String, basePath: String)] = [:]
        for branch in nonDefaultBranches {
            for (name, basePath) in projectNamesAndBasePaths(from: treeEntriesByBranch[branch] ?? []) {
                if projectBranch[name] == nil { projectBranch[name] = (branch, basePath) }
            }
        }
        for (name, basePath) in projectNamesAndBasePaths(from: treeEntriesByBranch[defaultBranch] ?? []) {
            projectBranch[name] = (defaultBranch, basePath)
        }

        let projects = try await withThrowingTaskGroup(of: ChainProject.self) { group in
            for (name, info) in projectBranch {
                let entries = treeEntriesByBranch[info.branch] ?? []
                group.addTask {
                    try await self.fetchChainProject(name: name, basePath: info.basePath, baseRef: info.branch, treeEntries: entries)
                }
            }
            var result: [ChainProject] = []
            for try await project in group {
                result.append(project)
            }
            return result.sorted { $0.name < $1.name }
        }

        return ChainListResult(projects: projects, failures: failures)
    }

    // MARK: - Private

    private func loadChainTreeEntries(branch: String) async throws -> [GitTreeEntry] {
        let head = try await gitHubPRService.branchHead(branch: branch, ttl: 300)
        let allEntries = try await gitHubPRService.gitTree(treeSHA: head.treeSHA)
        return allEntries.filter {
            ($0.path.hasPrefix(ClaudeChainConstants.projectDirectoryPrefix + "/") || $0.path.hasPrefix(ClaudeChainConstants.sweepChainDirectory + "/")) && $0.type == "blob"
        }
    }

    private func projectNamesAndBasePaths(from entries: [GitTreeEntry]) -> [(name: String, basePath: String)] {
        var seen: Set<String> = []
        var result: [(name: String, basePath: String)] = []
        for entry in entries {
            let match: (name: String, dir: String)?
            if let name = MarkdownClaudeChainSource.matchesSpecPath(entry.path) {
                match = (name, ClaudeChainConstants.projectDirectoryPrefix)
            } else if let name = SweepClaudeChainSource.matchesSpecPath(entry.path) {
                match = (name, ClaudeChainConstants.sweepChainDirectory)
            } else {
                match = nil
            }
            if let (name, dir) = match, seen.insert(name).inserted {
                result.append((name, "\(dir)/\(name)"))
            }
        }
        return result
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

    private func fetchChainProject(name: String, basePath: String, baseRef: String, treeEntries: [GitTreeEntry]) async throws -> ChainProject {
        let project = Project(name: name, basePath: basePath)
        let specPath = project.specPath
        let configPath = project.configPath
        let kindBadge: String? = basePath.hasPrefix(ClaudeChainConstants.sweepChainDirectory) ? "sweep" : nil

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
                kindBadge: kindBadge,
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
            kindBadge: kindBadge,
            maxOpenPRs: maxOpenPRs
        )
    }
}
