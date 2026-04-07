import AIOutputSDK
import CredentialService
import CryptoKit
import Foundation
import GitSDK
import Logging
import PipelineSDK
import PipelineService
import PlanService
import RepositorySDK
import UseCaseSDK

public struct PlanService: UseCase {

    // MARK: - Generate types

    public struct GenerateOptions: Sendable {
        public let prompt: String
        public let repositories: [RepositoryConfiguration]
        public let selectedRepository: RepositoryConfiguration?

        public init(
            prompt: String,
            repositories: [RepositoryConfiguration],
            selectedRepository: RepositoryConfiguration? = nil
        ) {
            self.prompt = prompt
            self.repositories = repositories
            self.selectedRepository = selectedRepository
        }
    }

    public struct GenerateResult: Sendable {
        public let planURL: URL
        public let repository: RepositoryConfiguration
        public let repoMatch: RepoMatch
        public let plan: GeneratedPlan

        public init(planURL: URL, repository: RepositoryConfiguration, repoMatch: RepoMatch, plan: GeneratedPlan) {
            self.planURL = planURL
            self.repository = repository
            self.repoMatch = repoMatch
            self.plan = plan
        }
    }

    public enum GenerateProgress: Sendable {
        case matchingRepo
        case matchedRepo(repoId: String, interpretedRequest: String)
        case generatingPlan
        case generatedPlan(filename: String)
        case writingPlan
        case completed(planURL: URL, repository: RepositoryConfiguration)
    }

    public enum GenerateError: Error, LocalizedError {
        case repoNotFound(String)
        case writeError(String)

        public var errorDescription: String? {
            switch self {
            case .repoNotFound(let id):
                return "Repository '\(id)' not found in configured repositories"
            case .writeError(let detail):
                return "Failed to write plan: \(detail)"
            }
        }
    }

    // MARK: - Execute types

    public enum ExecuteMode: Sendable {
        case all
        case next
    }

    public struct ExecuteOptions: Sendable {
        public let executeMode: ExecuteMode
        public let planPath: URL
        public let repoPath: URL?
        public let maxMinutes: Int
        public let repository: RepositoryConfiguration?
        public let stopAfterArchitectureDiagram: Bool
        public let worktreeOptions: WorktreeOptions?

        public init(
            executeMode: ExecuteMode = .all,
            planPath: URL,
            repoPath: URL? = nil,
            maxMinutes: Int = 90,
            repository: RepositoryConfiguration? = nil,
            stopAfterArchitectureDiagram: Bool = false,
            worktreeOptions: WorktreeOptions? = nil
        ) {
            self.executeMode = executeMode
            self.planPath = planPath
            self.repoPath = repoPath
            self.maxMinutes = maxMinutes
            self.repository = repository
            self.stopAfterArchitectureDiagram = stopAfterArchitectureDiagram
            self.worktreeOptions = worktreeOptions
        }
    }

    public struct ExecuteResult: Sendable {
        public let phasesExecuted: Int
        public let totalPhases: Int
        public let allCompleted: Bool
        public let stoppedForArchitectureReview: Bool
        public let totalSeconds: Int

        public init(
            phasesExecuted: Int,
            totalPhases: Int,
            allCompleted: Bool,
            stoppedForArchitectureReview: Bool = false,
            totalSeconds: Int
        ) {
            self.phasesExecuted = phasesExecuted
            self.totalPhases = totalPhases
            self.allCompleted = allCompleted
            self.stoppedForArchitectureReview = stoppedForArchitectureReview
            self.totalSeconds = totalSeconds
        }
    }

    public enum ExecuteProgress: Sendable {
        case fetchingStatus
        case phaseOverview(phases: [PlanPhase])
        case startingPhase(index: Int, total: Int, description: String)
        case phaseOutput(text: String)
        case phaseStreamEvent(AIStreamEvent)
        case phaseCompleted(index: Int, elapsedSeconds: Int, totalElapsedSeconds: Int)
        case phaseFailed(index: Int, description: String, error: String)
        case allCompleted(phasesExecuted: Int, totalSeconds: Int)
        case uncommittedChanges(files: [String])
    }

    public enum ExecuteError: Error, LocalizedError {
        case phaseFailed(index: Int, description: String, underlyingError: String)
        case planNotFound(String)
        case timeLimitReached(phasesExecuted: Int, totalPhases: Int, maxMinutes: Int)

        public var errorDescription: String? {
            switch self {
            case .phaseFailed(let index, let description, let underlyingError):
                return "Phase \(index + 1) failed: \(description) — \(underlyingError)"
            case .planNotFound(let path):
                return "Planning document not found: \(path)"
            case .timeLimitReached(let phasesExecuted, let totalPhases, let maxMinutes):
                return "Time limit of \(maxMinutes)m reached after \(phasesExecuted)/\(totalPhases) phases"
            }
        }
    }

    // MARK: - Dependencies

    private let client: any AIClient
    private let logger = Logger(label: "PlanService")
    private let resolveProposedDirectory: @Sendable (RepositoryConfiguration) throws -> URL

    public init(
        client: any AIClient,
        resolveProposedDirectory: @escaping @Sendable (RepositoryConfiguration) throws -> URL
    ) {
        self.client = client
        self.resolveProposedDirectory = resolveProposedDirectory
    }

    // MARK: - Generate

    public func generate(
        options: GenerateOptions,
        onProgress: (@Sendable (GenerateProgress) -> Void)? = nil
    ) async throws -> GenerateResult {
        var context = PipelineContext()
        context[PlanGenerationNode.inputKey] = options

        let node = PlanGenerationNode(
            client: client,
            generateProgressHandler: { progress in onProgress?(progress) },
            resolveProposedDirectory: resolveProposedDirectory
        )

        let configuration = PipelineConfiguration(provider: client)
        let runner = PipelineRunner()
        let finalContext = try await runner.run(
            nodes: [node],
            configuration: configuration,
            initialContext: context,
            onProgress: { _ in }
        )

        guard let result = finalContext[PlanGenerationNode.outputKey] else {
            throw GenerateError.writeError("Plan generation did not produce a result")
        }
        return result
    }

    // MARK: - Build execute pipeline

    public func buildExecutePipeline(
        options: ExecuteOptions,
        pendingTasksProvider: (@Sendable () async -> [String])? = nil
    ) async throws -> PipelineBlueprint {
        // 1. Pre-read phases to build the initial node manifest
        let pipelineSource = MarkdownPipelineSource(fileURL: options.planPath, format: .phase)
        let loadedPipeline = try await pipelineSource.load()
        let steps = loadedPipeline.steps.compactMap { $0 as? CodeChangeStep }
        let initialNodeManifest = steps.enumerated().map { idx, step in
            NodeManifest(id: step.id, displayName: "Phase \(idx + 1): \(step.description)")
        }

        // 2. Resolve credentials
        var environment: [String: String]?
        if let credentialAccount = options.repository?.credentialAccount {
            let resolver = CredentialResolver(
                settingsService: SecureSettingsService(),
                githubAccount: credentialAccount
            )
            if case .token(let token) = resolver.getGitHubAuth() {
                var env = ProcessInfo.processInfo.environment
                env["GH_TOKEN"] = token
                environment = env
            }
        }

        // 3. Build instruction enricher: injects plan path, phase number, skills, commit format
        let planPath = options.planPath
        let instructionBuilder: @Sendable (PendingTask) -> String = { task in
            let phaseIndex = Int(task.id) ?? 0
            let ghInstructions = "\nWhen creating pull requests, ALWAYS use `gh pr create --draft`."
            let skillsToRead = PlanService.parseSkillsToRead(planPath: planPath, phaseIndex: phaseIndex)
            let skillsInstruction = skillsToRead.isEmpty ? "" : """

            Before implementing, read these skills for relevant conventions: \(skillsToRead.joined(separator: ", "))
            """

            return """
            Look at \(planPath.path) for background.

            You are working on Phase \(phaseIndex + 1): \(task.instructions)
            \(skillsInstruction)
            Complete ONLY this phase by:
            1. Implementing the required changes
            2. Ensuring the build succeeds
            3. Updating the markdown document:
               - Change `## - [ ]` to `## - [x]` for this phase
               - Add completion notes below the phase heading:
                 **Skills used**: `skill-a`, `skill-b` (list skills you actually read/applied, or "none")
                 **Principles applied**: Brief note about key decisions made
            4. Committing your changes with message: "Complete Phase \(phaseIndex + 1): \(task.instructions)"
            \(ghInstructions)

            Return success: true if the phase was completed successfully, false otherwise.
            """
        }

        // 4. Build betweenTasks closure when a task queue is provided
        let betweenTasks: (@Sendable () async throws -> Void)?
        if let provider = pendingTasksProvider {
            let planURL = options.planPath
            let repoPath = options.repoPath
            let aiClient = client
            betweenTasks = {
                let taskDescriptions = await provider()
                guard !taskDescriptions.isEmpty else { return }
                let integrateOptions = IntegrateTaskIntoPlanUseCase.Options(
                    planPath: planURL,
                    repoPath: repoPath,
                    taskDescriptions: taskDescriptions
                )
                _ = try await IntegrateTaskIntoPlanUseCase(client: aiClient).run(integrateOptions)
            }
        } else {
            betweenTasks = nil
        }

        // 5–6. Wrap the task source in a pipeline node
        let taskSource = MarkdownTaskSource(
            fileURL: options.planPath,
            format: .phase,
            instructionBuilder: instructionBuilder
        )
        let taskSourceNode = TaskSourceNode(
            id: "task-source",
            displayName: "Load Phases",
            source: taskSource
        )

        // 7. Assemble and return the blueprint
        let executionMode: PipelineConfiguration.ExecutionMode = options.executeMode == .all ? .all : .nextOnly
        let configuration = PipelineConfiguration(
            executionMode: executionMode,
            maxMinutes: options.maxMinutes,
            provider: client,
            workingDirectory: options.repoPath?.path,
            environment: environment,
            betweenTasks: betweenTasks
        )

        var nodes: [any PipelineNode] = []
        if let wo = options.worktreeOptions {
            nodes.append(WorktreeNode(options: wo, gitClient: GitClient()))
        }
        nodes.append(taskSourceNode)

        return PipelineBlueprint(
            nodes: nodes,
            configuration: configuration,
            initialNodeManifest: initialNodeManifest
        )
    }

    // MARK: - Worktree

    public static func worktreeBranchName(for planURL: URL) -> String {
        let stem = planURL.deletingPathExtension().lastPathComponent
        let normalized = stem.split(separator: " ").joined(separator: " ")
        let data = normalized.data(using: .utf8) ?? Data()
        let hash = SHA256.hash(data: data)
        let identifier = hash.compactMap { String(format: "%02x", $0) }.joined().prefix(8).lowercased()
        return "plan-\(identifier)"
    }

    static func parseSkillsToRead(planPath: URL, phaseIndex: Int) -> [String] {
        guard let content = try? String(contentsOf: planPath, encoding: .utf8) else { return [] }

        let lines = content.components(separatedBy: "\n")
        var currentPhase = -1
        for line in lines {
            if line.hasPrefix("## - [") {
                currentPhase += 1
            }
            if currentPhase == phaseIndex,
               let range = line.range(of: "**Skills to read**:", options: .caseInsensitive) {
                let after = line[range.upperBound...]
                return after
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "`", with: "") }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }

}
