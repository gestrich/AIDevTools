import AIOutputSDK
import CredentialService
import Foundation
import GitSDK
import Logging
import PlanService
import PipelineSDK
import RepositorySDK
import UseCaseSDK

@available(*, deprecated, renamed: "PlanService")
public struct ExecutePlanUseCase: UseCase {

    public enum ExecuteMode: Sendable {
        case all
        case next
    }

    public struct Options: Sendable {
        public let executeMode: ExecuteMode
        public let planPath: URL
        public let repoPath: URL?
        public let maxMinutes: Int
        public let repository: RepositoryConfiguration?
        public let stopAfterArchitectureDiagram: Bool

        public init(
            executeMode: ExecuteMode = .all,
            planPath: URL,
            repoPath: URL? = nil,
            maxMinutes: Int = 90,
            repository: RepositoryConfiguration? = nil,
            stopAfterArchitectureDiagram: Bool = false
        ) {
            self.executeMode = executeMode
            self.planPath = planPath
            self.repoPath = repoPath
            self.maxMinutes = maxMinutes
            self.repository = repository
            self.stopAfterArchitectureDiagram = stopAfterArchitectureDiagram
        }
    }

    public struct Result: Sendable {
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

    public enum Progress: Sendable {
        case fetchingStatus
        case phaseOverview(phases: [PhaseStatus])
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

    private let client: any AIClient
    private let completedDirectory: URL?
    private let dataPath: URL
    private let gitClient: GitClient
    private let logger = Logger(label: "ExecutePlanUseCase")

    public init(
        client: any AIClient,
        completedDirectory: URL? = nil,
        dataPath: URL,
        gitClient: GitClient = GitClient()
    ) {
        self.client = client
        self.completedDirectory = completedDirectory
        self.dataPath = dataPath
        self.gitClient = gitClient
    }

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil,
        betweenPhases: (@Sendable () async throws -> Void)? = nil
    ) async throws -> Result {
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

        let pipelineSource = MarkdownPipelineSource(fileURL: options.planPath, format: .phase)
        onProgress?(.fetchingStatus)
        var statusResponse = try await loadPhaseStatus(from: pipelineSource)
        var phases = statusResponse.phases
        var nextIndex = statusResponse.nextPhaseIndex

        onProgress?(.phaseOverview(phases: phases))

        if nextIndex == -1 {
            let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
            onProgress?(.allCompleted(phasesExecuted: 0, totalSeconds: totalSeconds))
            return Result(phasesExecuted: 0, totalPhases: phases.count, allCompleted: true, totalSeconds: totalSeconds)
        }

        var phasesExecuted = 0

        while nextIndex != -1 {
            let elapsed = Date().timeIntervalSince(scriptStart)
            if Int(elapsed) >= maxRuntimeSeconds {
                let remaining = phases.filter { !$0.isCompleted }.count
                let totalSeconds = Int(elapsed)
                throw ExecuteError.timeLimitReached(phasesExecuted: phasesExecuted, totalPhases: phases.count, maxMinutes: options.maxMinutes)
            }

            let phase = phases[nextIndex]
            logger.info("Phase \(nextIndex + 1)/\(phases.count) started: \(phase.description)", metadata: [
                "plan": "\(options.planPath.lastPathComponent)"
            ])
            onProgress?(.startingPhase(index: nextIndex, total: phases.count, description: phase.description))

            let phaseStart = Date()
            let outputAccumulator = OutputAccumulator()

            let phaseResult: PhaseResult
            do {
                phaseResult = try await executePhase(
                    planPath: options.planPath,
                    phaseIndex: nextIndex,
                    description: phase.description,
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
                let logPath = writePhaseLog(output: await outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
                logger.error("Phase \(nextIndex + 1) failed: \(error.localizedDescription)", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)",
                    "logFile": "\(logPath?.path ?? "none")",
                ])
                onProgress?(.phaseFailed(index: nextIndex, description: phase.description, error: error.localizedDescription))
                onProgress?(.phaseCompleted(index: nextIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
                throw ExecuteError.phaseFailed(index: nextIndex, description: phase.description, underlyingError: error.localizedDescription)
            }

            let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
            let totalElapsed = Int(Date().timeIntervalSince(scriptStart))

            if !phaseResult.success {
                let logPath = writePhaseLog(output: await outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
                let reason = "Phase reported failure"
                logger.error("Phase \(nextIndex + 1) failed: \(reason)", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)",
                    "logFile": "\(logPath?.path ?? "none")",
                ])
                onProgress?(.phaseFailed(index: nextIndex, description: phase.description, error: reason))
                onProgress?(.phaseCompleted(index: nextIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
                throw ExecuteError.phaseFailed(index: nextIndex, description: phase.description, underlyingError: reason)
            }

            // Ensure the phase checkbox is marked complete in the source
            let completedStep = CodeChangeStep(
                id: String(nextIndex),
                description: phase.description,
                isCompleted: false,
                prompt: phase.description,
                skills: [],
                context: .empty
            )
            try await pipelineSource.markStepCompleted(completedStep)

            writePhaseLog(output: await outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
            logger.info("Phase \(nextIndex + 1) completed in \(phaseElapsed)s", metadata: [
                "plan": "\(options.planPath.lastPathComponent)"
            ])
            onProgress?(.phaseCompleted(index: nextIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
            phasesExecuted += 1

            if options.executeMode == .next {
                let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
                return Result(phasesExecuted: 1, totalPhases: phases.count, allCompleted: false, totalSeconds: totalSeconds)
            }

            if options.stopAfterArchitectureDiagram && architectureDiagramExists(planPath: options.planPath) {
                let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
                logger.info("Stopping after architecture diagram detected", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)"
                ])
                return Result(
                    phasesExecuted: phasesExecuted,
                    totalPhases: phases.count,
                    allCompleted: false,
                    stoppedForArchitectureReview: true,
                    totalSeconds: totalSeconds
                )
            }

            try await betweenPhases?()

            onProgress?(.fetchingStatus)
            statusResponse = try await loadPhaseStatus(from: pipelineSource)
            phases = statusResponse.phases
            nextIndex = statusResponse.nextPhaseIndex

            if nextIndex != -1 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }

        let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
        let allDone = nextIndex == -1

        if allDone {
            onProgress?(.allCompleted(phasesExecuted: phasesExecuted, totalSeconds: totalSeconds))
            moveToCompleted(planPath: options.planPath, completedDirectory: completedDirectory)
        }

        return Result(
            phasesExecuted: phasesExecuted,
            totalPhases: phases.count,
            allCompleted: allDone,
            totalSeconds: totalSeconds
        )
    }

    // MARK: - Phase Status

    private func loadPhaseStatus(from source: MarkdownPipelineSource) async throws -> PhaseStatusResponse {
        let pipeline = try await source.load()
        let phases = pipeline.steps.compactMap { step -> PhaseStatus? in
            guard let codeStep = step as? CodeChangeStep else { return nil }
            return PhaseStatus(
                description: codeStep.description,
                status: codeStep.isCompleted ? "completed" : "pending"
            )
        }
        let nextPhaseIndex = phases.firstIndex(where: { !$0.isCompleted }) ?? -1
        return PhaseStatusResponse(phases: phases, nextPhaseIndex: nextPhaseIndex)
    }

    // MARK: - AI Calls

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

        // Resolve GH_TOKEN from credential account
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
               let range = line.range(of: "**Skills to read**:", options: .caseInsensitive)
                ?? line.range(of: "**Skills to read**:", options: .caseInsensitive) {
                let after = line[range.upperBound...]
                return after
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "`", with: "") }
                    .filter { !$0.isEmpty }
            }
        }
        return []
    }

    // MARK: - Architecture Diagram Detection

    private func architectureDiagramExists(planPath: URL) -> Bool {
        let planName = planPath.deletingPathExtension().lastPathComponent
        let architectureURL = planPath
            .deletingLastPathComponent()
            .appendingPathComponent("\(planName)-architecture.json")
        return FileManager.default.fileExists(atPath: architectureURL.path)
    }

    // MARK: - Log Directory

    public static func logDirectory(dataPath: URL, repoName: String, planURL: URL) -> URL {
        let planName = planURL.deletingPathExtension().lastPathComponent
        return dataPath
            .appendingPathComponent(repoName)
            .appendingPathComponent("plan-logs")
            .appendingPathComponent(planName)
    }

    // MARK: - Logging

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

    // MARK: - Completion Handling

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

            // Also move architecture JSON if it exists
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
