import AIOutputSDK
import ClaudeChainSDK
import ClaudeChainService
import CredentialService
import Foundation
import GitHubService
import GitSDK
import PipelineSDK
import PipelineService

public struct ChainRunOptions: Sendable {
    public let baseBranch: String
    public let branchName: String?
    public let dryRun: Bool
    public let githubAccount: String?
    public let projectName: String
    public let repoPath: URL
    public let stagingOnly: Bool

    public init(
        baseBranch: String,
        branchName: String? = nil,
        dryRun: Bool = false,
        githubAccount: String? = nil,
        projectName: String,
        repoPath: URL,
        stagingOnly: Bool = false
    ) {
        self.baseBranch = baseBranch
        self.branchName = branchName
        self.dryRun = dryRun
        self.githubAccount = githubAccount
        self.projectName = projectName
        self.repoPath = repoPath
        self.stagingOnly = stagingOnly
    }
}

public enum ChainSource: Sendable {
    case local
    case remote
}

public enum ChainKind: Sendable {
    case all
    case spec
    case sweep
}

public struct ClaudeChainService {
    private let client: any AIClient
    private let git: GitClient
    private let localSource: (any ChainProjectSource)?
    private let remoteSource: (any ChainProjectSource)?

    public init(client: any AIClient, git: GitClient = GitClient()) {
        self.client = client
        self.git = git
        self.localSource = nil
        self.remoteSource = nil
    }

    public init(
        client: any AIClient,
        git: GitClient = GitClient(),
        localSource: any ChainProjectSource
    ) {
        self.client = client
        self.git = git
        self.localSource = localSource
        self.remoteSource = nil
    }

    public init(
        client: any AIClient,
        git: GitClient = GitClient(),
        localSource: any ChainProjectSource,
        remoteSource: any ChainProjectSource
    ) {
        self.client = client
        self.git = git
        self.localSource = localSource
        self.remoteSource = remoteSource
    }

    public init(client: any AIClient, git: GitClient = GitClient(), repoPath: URL) {
        self.init(
            client: client,
            git: git,
            localSource: LocalChainProjectSource(repoPath: repoPath)
        )
    }

    public init(client: any AIClient, git: GitClient = GitClient(), repoPath: URL, prService: any GitHubPRServiceProtocol) {
        self.init(
            client: client,
            git: git,
            localSource: LocalChainProjectSource(repoPath: repoPath),
            remoteSource: GitHubChainProjectSource(gitHubPRService: prService)
        )
    }

    // MARK: - Chain listing

    public func listChains(source: ChainSource, kind: ChainKind = .all, useCache: Bool = false) async throws -> ChainListResult {
        var result: ChainListResult
        switch source {
        case .local:
            result = try await listLocalChains()
        case .remote:
            guard let remoteSource else {
                throw ChainServiceError.missingSource(sourceType: "remote")
            }
            result = try await remoteSource.listChains(useCache: useCache)
            if let localSource {
                result = await mergeSweepData(from: localSource, into: result)
            }
        }
        let filtered = result.projects.filter { project in
            switch kind {
            case .all: return true
            case .spec: return project.kindBadge == nil
            case .sweep: return project.kindBadge != nil
            }
        }
        return ChainListResult(projects: filtered, failures: result.failures)
    }

    // MARK: - Project detection from changed file paths

    public func detectLocalProjects(fromChangedPaths paths: [String]) async throws -> [Project] {
        let result = try await listLocalChains()
        return result.projects
            .filter { project in paths.contains(project.specPath) }
            .map { Project(name: $0.name, basePath: $0.basePath) }
            .sorted { $0.name < $1.name }
    }

    // MARK: - Private

    private func mergeSweepData(from localSource: any ChainProjectSource, into remoteResult: ChainListResult) async -> ChainListResult {
        let localResult = (try? await localSource.listChains(useCache: false)) ?? ChainListResult(projects: [], failures: [])
        let localByName = Dictionary(uniqueKeysWithValues: localResult.projects.map { ($0.name, $0) })

        let merged = remoteResult.projects.map { remote -> ChainProject in
            guard remote.kindBadge == "sweep", let local = localByName[remote.name] else {
                return remote
            }
            return ChainProject(merging: local, into: remote)
        }
        return ChainListResult(projects: merged, failures: remoteResult.failures)
    }

    private func listLocalChains() async throws -> ChainListResult {
        guard let localSource else {
            throw ChainServiceError.missingSource(sourceType: "local")
        }
        return try await localSource.listChains(useCache: false)
    }

    private func findLocalProject(named name: String, repoPath: URL) async throws -> ChainProject {
        let source = localSource ?? LocalChainProjectSource(repoPath: repoPath)
        let result = try await source.listChains(useCache: false)
        guard let project = result.projects.first(where: { $0.name == name }) else {
            throw ChainServiceError.projectNotFound(name: name)
        }
        return project
    }

    // MARK: - Pipeline building

    public func buildPipeline(for task: ChainTask, options: ChainRunOptions) async throws -> PipelineBlueprint {
        let repoDir = options.repoPath.path
        let chainProject = try await findLocalProject(named: options.projectName, repoPath: options.repoPath)
        let project = Project(name: options.projectName, basePath: chainProject.basePath)
        let repository = ProjectRepository(repo: "")
        let projectConfig = try? repository.loadLocalConfiguration(project: project)

        // Fetch + checkout base branch so spec.md reflects latest remote state
        try await git.fetch(remote: "origin", branch: options.baseBranch, workingDirectory: repoDir)
        try await git.checkout(ref: "FETCH_HEAD", workingDirectory: repoDir)

        // Create feature branch
        let taskHash = TaskService.generateTaskHash(description: task.description)
        let branchName = PRService.formatBranchName(projectName: options.projectName, taskHash: taskHash)
        try await git.checkout(ref: branchName, forceCreate: true, workingDirectory: repoDir)

        // Resolve credentials
        var environment: [String: String]?
        if let githubAccount = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                var env = ProcessInfo.processInfo.environment
                env["GH_TOKEN"] = token
                environment = env
            }
        }

        // Load spec content for instruction enrichment
        let spec = try? repository.loadLocalSpec(project: project)
        let specContent = spec?.content ?? ""
        let taskDescription = task.description

        let instructionBuilder: @Sendable (PendingTask) -> String = { pendingTask in
            """
            Complete the following task from spec.md:

            Task: \(pendingTask.instructions)

            Instructions: Read the entire spec.md file below to understand both WHAT to do and HOW to do it. \
            Follow all guidelines and patterns specified in the document.

            --- BEGIN spec.md ---
            \(specContent)
            --- END spec.md ---

            Now complete the task '\(taskDescription)' following all the details and instructions in the spec.md file above.
            """
        }

        // task.index is 1-based (from SpecTask); MarkdownTaskSource expects 0-based (matches CodeChangeStep.id)
        let specURL = URL(fileURLWithPath: project.specPath)
        let taskSource = MarkdownTaskSource(
            fileURL: specURL,
            format: .task,
            taskIndex: task.index - 1,
            instructionBuilder: instructionBuilder
        )

        let taskSourceNode = TaskSourceNode(
            id: "task-source",
            displayName: "Task: \(task.description)",
            source: taskSource
        )

        var nodes: [any PipelineNode] = [taskSourceNode]
        var manifests: [NodeManifest] = [
            NodeManifest(id: "task-source", displayName: "Task: \(task.description)")
        ]

        if !options.stagingOnly {
            let prConfiguration = PRConfiguration(
                assignees: projectConfig?.assignees ?? [],
                labels: [Constants.defaultPRLabel],
                maxOpenPRs: projectConfig?.maxOpenPRs,
                reviewers: projectConfig?.reviewers ?? []
            )
            let prStep = PRStep(
                id: "pr-step",
                displayName: "Create PR",
                baseBranch: options.baseBranch,
                configuration: prConfiguration,
                gitClient: git,
                projectName: options.projectName,
                taskDescription: task.description
            )
            let commentStep = ChainPRCommentStep(
                id: "pr-comment-step",
                displayName: "Post PR Comment",
                baseBranch: options.baseBranch,
                client: client,
                gitClient: git,
                projectName: options.projectName,
                taskDescription: task.description,
                dryRun: options.dryRun
            )
            nodes.append(prStep)
            nodes.append(commentStep)
            manifests.append(NodeManifest(id: "pr-step", displayName: "Create PR"))
            manifests.append(NodeManifest(id: "pr-comment-step", displayName: "Post PR Comment"))
        }

        let configuration = PipelineConfiguration(
            executionMode: .nextOnly,
            provider: client,
            workingDirectory: repoDir,
            environment: environment
        )

        return PipelineBlueprint(
            nodes: nodes,
            configuration: configuration,
            initialNodeManifest: manifests
        )
    }

    public func buildFinalizePipeline(for task: ChainTask, options: ChainRunOptions) async throws -> PipelineBlueprint {
        let repoDir = options.repoPath.path
        let chainProject = try await findLocalProject(named: options.projectName, repoPath: options.repoPath)
        let project = Project(name: options.projectName, basePath: chainProject.basePath)
        let repository = ProjectRepository(repo: "")
        let projectConfig = try? repository.loadLocalConfiguration(project: project)

        // Resolve credentials
        var environment: [String: String]?
        if let githubAccount = options.githubAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: githubAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                var env = ProcessInfo.processInfo.environment
                env["GH_TOKEN"] = token
                environment = env
            }
        }

        // Checkout existing staged branch
        if let branchName = options.branchName {
            try await git.checkout(ref: branchName, workingDirectory: repoDir)
        }

        // Mark spec.md checkbox complete and commit before building the blueprint
        let specURL = URL(fileURLWithPath: project.specPath)
        let pipelineSource = MarkdownPipelineSource(fileURL: specURL, format: .task, appendCreatePRStep: false)
        let pipeline = try await pipelineSource.load()
        let codeSteps = pipeline.steps.compactMap { $0 as? CodeChangeStep }
        if let step = codeSteps.first(where: { $0.description == task.description }) {
            try await pipelineSource.markStepCompleted(step)
            try await git.add(files: [specURL.path], workingDirectory: repoDir)
            let staged = try await git.diffCachedNames(workingDirectory: repoDir)
            if !staged.isEmpty {
                let stepIndex = (Int(step.id) ?? 0) + 1
                try await git.commit(
                    message: "Mark task \(stepIndex) as complete in spec.md",
                    workingDirectory: repoDir
                )
            }
        }

        // Blueprint: just PRStep (push + PR creation; code already committed)
        let prConfiguration = PRConfiguration(
            assignees: projectConfig?.assignees ?? [],
            labels: [Constants.defaultPRLabel],
            maxOpenPRs: projectConfig?.maxOpenPRs,
            reviewers: projectConfig?.reviewers ?? []
        )
        let prStep = PRStep(
            id: "pr-step",
            displayName: "Create PR",
            baseBranch: options.baseBranch,
            configuration: prConfiguration,
            gitClient: git,
            projectName: options.projectName,
            taskDescription: task.description
        )
        let commentStep = ChainPRCommentStep(
            id: "pr-comment-step",
            displayName: "Post PR Comment",
            baseBranch: options.baseBranch,
            client: client,
            gitClient: git,
            projectName: options.projectName,
            taskDescription: task.description,
            dryRun: options.dryRun
        )

        let configuration = PipelineConfiguration(
            executionMode: .nextOnly,
            provider: client,
            workingDirectory: repoDir,
            environment: environment
        )

        return PipelineBlueprint(
            nodes: [prStep, commentStep],
            configuration: configuration,
            initialNodeManifest: [
                NodeManifest(id: "pr-step", displayName: "Create PR"),
                NodeManifest(id: "pr-comment-step", displayName: "Post PR Comment"),
            ]
        )
    }
}

private enum ChainServiceError: Error, LocalizedError {
    case missingSource(sourceType: String)
    case projectNotFound(name: String)

    var errorDescription: String? {
        switch self {
        case .missingSource(let sourceType):
            return "ClaudeChainService has no \(sourceType) source — use init(client:git:localSource:remoteSource:) or init(client:git:repoPath:prService:)"
        case .projectNotFound(let name):
            return "No local chain project named '\(name)' found — check that a spec.md exists in your claude-chain directory"
        }
    }
}
