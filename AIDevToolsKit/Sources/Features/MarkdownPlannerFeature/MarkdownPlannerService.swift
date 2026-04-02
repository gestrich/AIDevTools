import AIOutputSDK
import CredentialService
import Foundation
import GitSDK
import Logging
import MarkdownPlannerService
import PipelineSDK
import RepositorySDK
import UseCaseSDK

public struct MarkdownPlannerService: UseCase {

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
        public let useWorktree: Bool

        public init(
            executeMode: ExecuteMode = .all,
            planPath: URL,
            repoPath: URL? = nil,
            maxMinutes: Int = 90,
            repository: RepositoryConfiguration? = nil,
            stopAfterArchitectureDiagram: Bool = false,
            useWorktree: Bool = false
        ) {
            self.executeMode = executeMode
            self.planPath = planPath
            self.repoPath = repoPath
            self.maxMinutes = maxMinutes
            self.repository = repository
            self.stopAfterArchitectureDiagram = stopAfterArchitectureDiagram
            self.useWorktree = useWorktree
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
    private let completedDirectory: URL?
    private let dataPath: URL
    private let gitClient: GitClient
    private let logger = Logger(label: "MarkdownPlannerService")
    private let resolveProposedDirectory: @Sendable (RepositoryConfiguration) throws -> URL

    public init(
        client: any AIClient,
        completedDirectory: URL? = nil,
        dataPath: URL,
        gitClient: GitClient = GitClient(),
        resolveProposedDirectory: @escaping @Sendable (RepositoryConfiguration) throws -> URL
    ) {
        self.client = client
        self.completedDirectory = completedDirectory
        self.dataPath = dataPath
        self.gitClient = gitClient
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

    // MARK: - Execute

    public func execute(
        options: ExecuteOptions,
        onProgress: (@Sendable (ExecuteProgress) -> Void)? = nil,
        betweenPhases: (@Sendable () async throws -> Void)? = nil
    ) async throws -> ExecuteResult {
        guard FileManager.default.fileExists(atPath: options.planPath.path) else {
            throw ExecuteError.planNotFound(options.planPath.path)
        }

        let repository = options.repository
        let logDir: URL? = if let repoName = repository?.name {
            Self.logDirectory(dataPath: dataPath, repoName: repoName, planURL: options.planPath)
        } else {
            nil
        }

        if let repoPath = options.repoPath {
            let changedFiles = try await gitClient.status(workingDirectory: repoPath.path)
            if !changedFiles.isEmpty {
                onProgress?(.uncommittedChanges(files: changedFiles))
            }
        }

        let maxRuntimeSeconds = options.maxMinutes * 60
        let scriptStart = Date()

        // Load all phases for the initial overview
        onProgress?(.fetchingStatus)
        let initialPipeline = try await MarkdownPipelineSource(fileURL: options.planPath, format: .phase).load()
        var phases = initialPipeline.steps.compactMap { $0 as? CodeChangeStep }.enumerated().map { idx, step in
            PlanPhase(index: idx, description: step.description, isCompleted: step.isCompleted)
        }
        let totalPhases = phases.count

        onProgress?(.phaseOverview(phases: phases))

        guard phases.contains(where: { !$0.isCompleted }) else {
            let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
            onProgress?(.allCompleted(phasesExecuted: 0, totalSeconds: totalSeconds))
            return ExecuteResult(phasesExecuted: 0, totalPhases: totalPhases, allCompleted: true, totalSeconds: totalSeconds)
        }

        let taskSource = MarkdownTaskSource(fileURL: options.planPath, format: .phase)
        var phasesExecuted = 0

        while let task = try await taskSource.nextTask() {
            let elapsed = Date().timeIntervalSince(scriptStart)
            if Int(elapsed) >= maxRuntimeSeconds {
                throw ExecuteError.timeLimitReached(phasesExecuted: phasesExecuted, totalPhases: totalPhases, maxMinutes: options.maxMinutes)
            }

            let phaseIndex = Int(task.id) ?? 0
            logger.info("Phase \(phaseIndex + 1)/\(totalPhases) started: \(task.instructions)", metadata: [
                "plan": "\(options.planPath.lastPathComponent)"
            ])
            onProgress?(.startingPhase(index: phaseIndex, total: totalPhases, description: task.instructions))

            let phaseStart = Date()
            let outputAccumulator = OutputAccumulator()

            let phaseResult: PhaseResult
            do {
                phaseResult = try await executePhase(
                    planPath: options.planPath,
                    phaseIndex: phaseIndex,
                    description: task.instructions,
                    repoPath: options.repoPath,
                    repository: repository,
                    onOutput: { text in
                        Task { await outputAccumulator.append(text) }
                        onProgress?(.phaseOutput(text: text))
                    },
                    onStreamEvent: { event in
                        onProgress?(.phaseStreamEvent(event))
                    }
                )
            } catch {
                let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
                let totalElapsed = Int(Date().timeIntervalSince(scriptStart))
                writePhaseLog(output: await outputAccumulator.content, phaseIndex: phaseIndex, logDirectory: logDir)
                logger.error("Phase \(phaseIndex + 1) failed: \(error.localizedDescription)", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)"
                ])
                onProgress?(.phaseFailed(index: phaseIndex, description: task.instructions, error: error.localizedDescription))
                onProgress?(.phaseCompleted(index: phaseIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
                throw ExecuteError.phaseFailed(index: phaseIndex, description: task.instructions, underlyingError: error.localizedDescription)
            }

            let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
            let totalElapsed = Int(Date().timeIntervalSince(scriptStart))

            if !phaseResult.success {
                writePhaseLog(output: await outputAccumulator.content, phaseIndex: phaseIndex, logDirectory: logDir)
                let reason = "Phase reported failure"
                logger.error("Phase \(phaseIndex + 1) failed: \(reason)", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)"
                ])
                onProgress?(.phaseFailed(index: phaseIndex, description: task.instructions, error: reason))
                onProgress?(.phaseCompleted(index: phaseIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
                throw ExecuteError.phaseFailed(index: phaseIndex, description: task.instructions, underlyingError: reason)
            }

            try await taskSource.markComplete(task)

            if phaseIndex < phases.count {
                phases[phaseIndex] = PlanPhase(index: phaseIndex, description: phases[phaseIndex].description, isCompleted: true)
            }

            writePhaseLog(output: await outputAccumulator.content, phaseIndex: phaseIndex, logDirectory: logDir)
            logger.info("Phase \(phaseIndex + 1) completed in \(phaseElapsed)s", metadata: [
                "plan": "\(options.planPath.lastPathComponent)"
            ])
            onProgress?(.phaseCompleted(index: phaseIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
            phasesExecuted += 1

            if options.executeMode == .next {
                let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
                return ExecuteResult(phasesExecuted: 1, totalPhases: totalPhases, allCompleted: false, totalSeconds: totalSeconds)
            }

            if options.stopAfterArchitectureDiagram && architectureDiagramExists(planPath: options.planPath) {
                let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
                logger.info("Stopping after architecture diagram detected", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)"
                ])
                return ExecuteResult(
                    phasesExecuted: phasesExecuted,
                    totalPhases: totalPhases,
                    allCompleted: false,
                    stoppedForArchitectureReview: true,
                    totalSeconds: totalSeconds
                )
            }

            try await betweenPhases?()

            let hasMoreTasks = phases.indices.suffix(from: min(phaseIndex + 1, phases.count)).contains { !phases[$0].isCompleted }
            if hasMoreTasks {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
        onProgress?(.allCompleted(phasesExecuted: phasesExecuted, totalSeconds: totalSeconds))
        moveToCompleted(planPath: options.planPath, completedDirectory: completedDirectory)

        return ExecuteResult(
            phasesExecuted: phasesExecuted,
            totalPhases: totalPhases,
            allCompleted: true,
            totalSeconds: totalSeconds
        )
    }

    // MARK: - Log directory

    public static func logDirectory(dataPath: URL, repoName: String, planURL: URL) -> URL {
        let planName = planURL.deletingPathExtension().lastPathComponent
        return dataPath
            .appendingPathComponent(repoName)
            .appendingPathComponent("plan-logs")
            .appendingPathComponent(planName)
    }

    // MARK: - Private: phase execution

    private static let executionSchema = """
    {"type":"object","properties":{"success":{"type":"boolean","description":"Whether the phase was completed successfully"}},"required":["success"]}
    """

    private func executePhase(
        planPath: URL,
        phaseIndex: Int,
        description: String,
        repoPath: URL?,
        repository: RepositoryConfiguration?,
        onOutput: (@Sendable (String) -> Void)?,
        onStreamEvent: (@Sendable (AIStreamEvent) -> Void)?
    ) async throws -> PhaseResult {
        let ghInstructions = "\nWhen creating pull requests, ALWAYS use `gh pr create --draft`."

        var environment: [String: String]?
        if let credentialAccount = repository?.credentialAccount {
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

        let skillsToRead = Self.parseSkillsToRead(planPath: planPath, phaseIndex: phaseIndex)
        let skillsInstruction = skillsToRead.isEmpty ? "" : """

        Before implementing, read these skills for relevant conventions: \(skillsToRead.joined(separator: ", "))
        """

        let prompt = """
        Look at \(planPath.path) for background.

        You are working on Phase \(phaseIndex + 1): \(description)
        \(skillsInstruction)

        Complete ONLY this phase by:
        1. Implementing the required changes
        2. Ensuring the build succeeds
        3. Updating the markdown document:
           - Change `## - [ ]` to `## - [x]` for this phase
           - Add completion notes below the phase heading:
             **Skills used**: `skill-a`, `skill-b` (list skills you actually read/applied, or "none")
             **Principles applied**: Brief note about key decisions made
        4. Committing your changes with message: "Complete Phase \(phaseIndex + 1): \(description)"
        \(ghInstructions)

        Return success: true if the phase was completed successfully, false otherwise.
        """

        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            environment: environment,
            workingDirectory: repoPath?.path
        )

        let output = try await client.runStructured(
            PhaseResult.self,
            prompt: prompt,
            jsonSchema: Self.executionSchema,
            options: options,
            onOutput: onOutput,
            onStreamEvent: onStreamEvent
        )
        return output.value
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

    // MARK: - Private: architecture diagram detection

    private func architectureDiagramExists(planPath: URL) -> Bool {
        let planName = planPath.deletingPathExtension().lastPathComponent
        let architectureURL = planPath
            .deletingLastPathComponent()
            .appendingPathComponent("\(planName)-architecture.json")
        return FileManager.default.fileExists(atPath: architectureURL.path)
    }

    // MARK: - Private: logging

    @discardableResult
    private func writePhaseLog(output: String, phaseIndex: Int, logDirectory: URL?) -> URL? {
        guard let logDirectory, !output.isEmpty else { return nil }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let filePath = logDirectory.appendingPathComponent("phase-\(phaseIndex + 1).stdout")
            try output.write(to: filePath, atomically: true, encoding: .utf8)
            return filePath
        } catch {
            logger.warning("Failed to write phase log: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Private: completion handling

    private func moveToCompleted(planPath: URL, completedDirectory: URL?) {
        let fm = FileManager.default
        let completedDir = completedDirectory
            ?? planPath.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("completed")

        do {
            if !fm.fileExists(atPath: completedDir.path) {
                try fm.createDirectory(at: completedDir, withIntermediateDirectories: true)
            }
            let dest = completedDir.appendingPathComponent(planPath.lastPathComponent)
            try fm.moveItem(at: planPath, to: dest)

            let planName = planPath.deletingPathExtension().lastPathComponent
            let archSource = planPath.deletingLastPathComponent()
                .appendingPathComponent("\(planName)-architecture.json")
            if fm.fileExists(atPath: archSource.path) {
                let archDest = completedDir.appendingPathComponent("\(planName)-architecture.json")
                try fm.moveItem(at: archSource, to: archDest)
            }
        } catch {
            // Non-fatal: plan stays in proposed/
        }
    }
}
