import ClaudeChainSDK
import Foundation
import GitSDK
import PipelineSDK

/// `ClaudeChainSource` implementation for regular spec.md-driven ClaudeChain projects.
///
/// `nextTask()` returns one task then nil (single-task-per-invocation behavior).
/// Task selection skips tasks that already have an open remote branch.
public actor MarkdownClaudeChainSource: ClaudeChainSource {

    private let project: Project
    private let repoPath: URL
    private let git: GitClient
    private let taskIndex: Int?
    private var taskReturned = false
    private var returnedTask: PendingTask?

    public init(
        project: Project,
        repoPath: URL,
        git: GitClient = GitClient(),
        taskIndex: Int? = nil
    ) {
        self.project = project
        self.repoPath = repoPath
        self.git = git
        self.taskIndex = taskIndex
    }

    // MARK: - ClaudeChainSource

    public func loadProject() async throws -> ChainProject {
        let chainDir = repoPath.appendingPathComponent(ClaudeChainConstants.projectDirectoryPrefix).path
        let absoluteProject = Project(
            name: project.name,
            basePath: (chainDir as NSString).appendingPathComponent(project.name)
        )
        let githubClient = GitHubClient(workingDirectory: chainDir)
        let repository = ProjectRepository(
            repo: "",
            gitHubOperations: GitHubOperations(githubClient: githubClient)
        )
        guard let spec = try? repository.loadLocalSpec(project: absoluteProject) else {
            return ChainProject(
                name: project.name,
                specPath: absoluteProject.specPath,
                completedTasks: 0,
                pendingTasks: 0,
                totalTasks: 0
            )
        }
        let config = (try? repository.loadLocalConfiguration(project: absoluteProject))
            ?? ProjectConfiguration.default(project: absoluteProject)
        let baseBranch = config.getBaseBranch(defaultBaseBranch: ClaudeChainConstants.defaultBaseBranch)
        let tasks = spec.tasks.map { ChainTask(index: $0.index, description: $0.description, isCompleted: $0.isCompleted) }
        return ChainProject(
            name: project.name,
            specPath: absoluteProject.specPath,
            tasks: tasks,
            completedTasks: spec.completedTasks,
            pendingTasks: spec.pendingTasks,
            totalTasks: spec.totalTasks,
            baseBranch: baseBranch,
            kind: .regular,
            maxOpenPRs: config.maxOpenPRs
        )
    }

    /// Returns a basic unenriched project detail.
    ///
    /// For enriched PR data use `GetChainDetailUseCase` directly.
    public func loadDetail() async throws -> ChainProjectDetail {
        let chainProject = try await loadProject()
        let enrichedTasks = chainProject.tasks.map { EnrichedChainTask(task: $0) }
        return ChainProjectDetail(project: chainProject, enrichedTasks: enrichedTasks, actionItems: [])
    }

    // MARK: - TaskSource

    /// Returns the next pending task on the first call, then nil.
    ///
    /// Skips tasks that already have an open remote branch (already in progress).
    public func nextTask() async throws -> PendingTask? {
        guard !taskReturned else { return nil }

        let chainDir = repoPath.appendingPathComponent(ClaudeChainConstants.projectDirectoryPrefix).path
        let absoluteProject = Project(
            name: project.name,
            basePath: (chainDir as NSString).appendingPathComponent(project.name)
        )
        let githubClient = GitHubClient(workingDirectory: chainDir)
        let repository = ProjectRepository(
            repo: "",
            gitHubOperations: GitHubOperations(githubClient: githubClient)
        )
        guard let spec = try? repository.loadLocalSpec(project: absoluteProject) else {
            return nil
        }

        let specURL = URL(fileURLWithPath: absoluteProject.specPath)
        let pipelineSource = MarkdownPipelineSource(fileURL: specURL, format: .task, appendCreatePRStep: false)
        let pipeline = try await pipelineSource.load()
        let codeSteps = pipeline.steps.compactMap { $0 as? CodeChangeStep }

        let nextStep: CodeChangeStep?
        if let index = taskIndex {
            nextStep = codeSteps.first(where: { Int($0.id) == index - 1 && !$0.isCompleted })
        } else {
            let projectPattern = "claude-chain-\(project.name)-*"
            let existingBranches = Set(
                (try? await git.listRemoteBranches(matching: projectPattern, workingDirectory: repoPath.path)) ?? []
            )
            nextStep = codeSteps.first(where: { step in
                guard !step.isCompleted else { return false }
                let hash = generateTaskHash(step.description)
                let branch = "claude-chain-\(project.name)-\(hash)"
                return !existingBranches.contains(branch)
            })
        }

        guard let step = nextStep else { return nil }

        let taskHash = generateTaskHash(step.description)
        let fullPrompt = buildTaskPrompt(taskDescription: step.description, specContent: spec.content)
        let task = PendingTask(id: taskHash, instructions: fullPrompt, skills: step.skills)
        taskReturned = true
        returnedTask = task
        return task
    }

    public func markComplete(_ task: PendingTask) async throws {
        let chainDir = repoPath.appendingPathComponent(ClaudeChainConstants.projectDirectoryPrefix).path
        let absoluteProject = Project(
            name: project.name,
            basePath: (chainDir as NSString).appendingPathComponent(project.name)
        )
        let specURL = URL(fileURLWithPath: absoluteProject.specPath)
        let pipelineSource = MarkdownPipelineSource(fileURL: specURL, format: .task, appendCreatePRStep: false)
        let pipeline = try await pipelineSource.load()
        let codeSteps = pipeline.steps.compactMap { $0 as? CodeChangeStep }
        let taskHash = task.id
        guard let step = codeSteps.first(where: { generateTaskHash($0.description) == taskHash }) else {
            return
        }
        try await pipelineSource.markStepCompleted(step)
    }

    // MARK: - Helpers

    private func buildTaskPrompt(taskDescription: String, specContent: String) -> String {
        """
        Complete the following task from spec.md:

        Task: \(taskDescription)

        Instructions: Read the entire spec.md file below to understand both WHAT to do and HOW to do it. \
        Follow all guidelines and patterns specified in the document.

        --- BEGIN spec.md ---
        \(specContent)
        --- END spec.md ---

        Now complete the task '\(taskDescription)' following all the details and instructions in the spec.md file above.
        """
    }
}
