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
    private let repository: ProjectRepository
    private let git: GitClient
    private let taskIndex: Int?
    private var taskReturned = false

    public init(
        projectName: String,
        repoPath: URL,
        git: GitClient = GitClient(),
        taskIndex: Int? = nil
    ) {
        let chainDir = repoPath.appendingPathComponent(ClaudeChainConstants.projectDirectoryPrefix)
        let basePath = chainDir.appendingPathComponent(projectName).path
        self.project = Project(name: projectName, basePath: basePath)
        self.repoPath = repoPath
        let githubClient = GitHubClient(workingDirectory: chainDir.path)
        self.repository = ProjectRepository(repo: "", gitHubOperations: GitHubOperations(githubClient: githubClient))
        self.git = git
        self.taskIndex = taskIndex
    }

    // MARK: - ClaudeChainSource

    public let kindBadge: String? = nil

    public func loadProject() async throws -> ChainProject {
        guard let spec = try? repository.loadLocalSpec(project: project) else {
            return ChainProject(
                name: project.name,
                specPath: project.specPath,
                completedTasks: 0,
                pendingTasks: 0,
                totalTasks: 0
            )
        }
        let config = (try? repository.loadLocalConfiguration(project: project))
            ?? ProjectConfiguration.default(project: project)
        let baseBranch = config.getBaseBranch(defaultBaseBranch: ClaudeChainConstants.defaultBaseBranch)
        let tasks = spec.tasks.map { ChainTask(index: $0.index, description: $0.description, isCompleted: $0.isCompleted) }
        return ChainProject(
            name: project.name,
            specPath: project.specPath,
            tasks: tasks,
            completedTasks: spec.completedTasks,
            pendingTasks: spec.pendingTasks,
            totalTasks: spec.totalTasks,
            baseBranch: baseBranch,
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
        guard let task = try await findTask() else { return nil }
        taskReturned = true
        return task
    }

    private func findTask() async throws -> PendingTask? {
        guard let spec = try? repository.loadLocalSpec(project: project) else {
            return nil
        }

        let specURL = URL(fileURLWithPath: project.specPath)
        let pipelineSource = MarkdownPipelineSource(fileURL: specURL, format: .task, appendCreatePRStep: false)
        let pipeline = try await pipelineSource.load()
        let codeSteps = pipeline.steps.compactMap { $0 as? CodeChangeStep }

        let step: CodeChangeStep?
        if let index = taskIndex {
            step = codeSteps.first(where: { Int($0.id) == index - 1 && !$0.isCompleted })
        } else {
            step = try await nextPendingStep(from: codeSteps)
        }

        guard let step else { return nil }

        let taskHash = generateTaskHash(step.description)
        let fullPrompt = buildTaskPrompt(taskDescription: step.description, specContent: spec.content)
        return PendingTask(id: taskHash, instructions: fullPrompt, skills: step.skills)
    }

    private func nextPendingStep(from codeSteps: [CodeChangeStep]) async throws -> CodeChangeStep? {
        let projectPattern = "claude-chain-\(project.name)-*"
        let existingBranches = Set(
            (try? await git.listRemoteBranches(matching: projectPattern, workingDirectory: repoPath.path)) ?? []
        )
        return codeSteps.first(where: { step in
            guard !step.isCompleted else { return false }
            let branch = "claude-chain-\(project.name)-\(generateTaskHash(step.description))"
            return !existingBranches.contains(branch)
        })
    }

    public func markComplete(_ task: PendingTask) async throws {
        let specURL = URL(fileURLWithPath: project.specPath)
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
