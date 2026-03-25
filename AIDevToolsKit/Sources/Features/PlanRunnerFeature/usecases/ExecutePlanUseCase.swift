import Foundation
import ClaudeCLISDK
import GitSDK
import Logging
import PlanRunnerService
import RepositorySDK

public struct ExecutePlanUseCase: Sendable {

    public struct Options: Sendable {
        public let planPath: URL
        public let repoPath: URL?
        public let maxMinutes: Int
        public let repository: RepositoryInfo?
        public let stopAfterArchitectureDiagram: Bool
        public let useWorktree: Bool

        public init(
            planPath: URL,
            repoPath: URL? = nil,
            maxMinutes: Int = 90,
            repository: RepositoryInfo? = nil,
            stopAfterArchitectureDiagram: Bool = false,
            useWorktree: Bool = false
        ) {
            self.planPath = planPath
            self.repoPath = repoPath
            self.maxMinutes = maxMinutes
            self.repository = repository
            self.stopAfterArchitectureDiagram = stopAfterArchitectureDiagram
            self.useWorktree = useWorktree
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
        case phaseCompleted(index: Int, elapsedSeconds: Int, totalElapsedSeconds: Int)
        case phaseFailed(index: Int, description: String, error: String)
        case allCompleted(phasesExecuted: Int, totalSeconds: Int)
        case timeLimitReached(remaining: Int, totalSeconds: Int)
    }

    public enum ExecuteError: Error, LocalizedError {
        case phaseFailed(index: Int, description: String, underlyingError: String)
        case planNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .phaseFailed(let index, let description, let underlyingError):
                return "Phase \(index + 1) failed: \(description) — \(underlyingError)"
            case .planNotFound(let path):
                return "Planning document not found: \(path)"
            }
        }
    }

    private let claudeClient: ClaudeCLIClient
    private let completedDirectory: URL?
    private let dataPath: URL
    private let gitClient: GitClient
    private let logger = Logger(label: "PlanRunner")

    public init(
        claudeClient: ClaudeCLIClient = ClaudeCLIClient(),
        completedDirectory: URL? = nil,
        dataPath: URL,
        gitClient: GitClient = GitClient()
    ) {
        self.claudeClient = claudeClient
        self.completedDirectory = completedDirectory
        self.dataPath = dataPath
        self.gitClient = gitClient
    }

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
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

        let maxRuntimeSeconds = options.maxMinutes * 60
        let scriptStart = Date()

        onProgress?(.fetchingStatus)
        var statusResponse = try await getPhaseStatus(
            planPath: options.planPath,
            repoPath: options.repoPath
        )
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
                onProgress?(.timeLimitReached(remaining: remaining, totalSeconds: totalSeconds))
                return Result(phasesExecuted: phasesExecuted, totalPhases: phases.count, allCompleted: false, totalSeconds: totalSeconds)
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
                        outputAccumulator.append(text)
                        onProgress?(.phaseOutput(text: text))
                    }
                )
            } catch {
                let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
                let totalElapsed = Int(Date().timeIntervalSince(scriptStart))
                let logPath = writePhaseLog(output: outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
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
                let logPath = writePhaseLog(output: outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
                let reason = "Phase reported failure"
                logger.error("Phase \(nextIndex + 1) failed: \(reason)", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)",
                    "logFile": "\(logPath?.path ?? "none")",
                ])
                onProgress?(.phaseFailed(index: nextIndex, description: phase.description, error: reason))
                onProgress?(.phaseCompleted(index: nextIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
                throw ExecuteError.phaseFailed(index: nextIndex, description: phase.description, underlyingError: reason)
            }

            writePhaseLog(output: outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
            logger.info("Phase \(nextIndex + 1) completed in \(phaseElapsed)s", metadata: [
                "plan": "\(options.planPath.lastPathComponent)"
            ])
            onProgress?(.phaseCompleted(index: nextIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
            phasesExecuted += 1

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

            onProgress?(.fetchingStatus)
            statusResponse = try await getPhaseStatus(
                planPath: options.planPath,
                repoPath: options.repoPath
            )
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

    // MARK: - Claude Calls

    private static let statusSchema = """
    {"type":"object","properties":{"phases":{"type":"array","items":{"type":"object","properties":{"description":{"type":"string"},"status":{"type":"string","enum":["pending","in_progress","completed"]}},"required":["description","status"]}},"nextPhaseIndex":{"type":"integer","description":"Index of the next phase to execute (0-based), or -1 if all complete"}},"required":["phases","nextPhaseIndex"]}
    """

    private static let executionSchema = """
    {"type":"object","properties":{"success":{"type":"boolean","description":"Whether the phase was completed successfully"}},"required":["success"]}
    """

    private func getPhaseStatus(planPath: URL, repoPath: URL?) async throws -> PhaseStatusResponse {
        let prompt = """
        Look at \(planPath.path) and analyze the phased implementation plan.

        Return a JSON with:
        1. phases: Array of all phases with their description and current status (pending/in_progress/completed)
        2. nextPhaseIndex: The index (0-based) of the next phase to execute, or -1 if all phases are complete

        Determine status by checking if each phase has been marked as complete in the document.
        """

        var command = Claude(prompt: prompt)
        command.printMode = true
        command.verbose = true
        command.dangerouslySkipPermissions = true
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = Self.statusSchema

        let output = try await claudeClient.runStructured(
            PhaseStatusResponse.self,
            command: command,
            workingDirectory: repoPath?.path
        )
        return output.value
    }

    private func executePhase(
        planPath: URL,
        phaseIndex: Int,
        description: String,
        repoPath: URL?,
        repository: RepositoryInfo?,
        onOutput: (@Sendable (String) -> Void)?
    ) async throws -> PhaseResult {
        var ghInstructions = "\nWhen creating pull requests, ALWAYS use `gh pr create --draft`."
        if let githubUser = repository?.githubUser {
            ghInstructions += "\nBefore running any `gh` commands, first run `gh auth switch -u \(githubUser)`."
        }

        let prompt = """
        Look at \(planPath.path) for background.

        You are working on Phase \(phaseIndex + 1): \(description)

        Complete ONLY this phase by:
        1. Implementing the required changes
        2. Ensuring the build succeeds
        3. Updating the markdown document to mark this phase as completed with any relevant technical notes
        4. Committing your changes
        \(ghInstructions)

        Return success: true if the phase was completed successfully, false otherwise.
        """

        var command = Claude(prompt: prompt)
        command.printMode = true
        command.verbose = true
        command.dangerouslySkipPermissions = true
        command.outputFormat = ClaudeOutputFormat.streamJSON.rawValue
        command.jsonSchema = Self.executionSchema

        let output = try await claudeClient.runStructured(
            PhaseResult.self,
            command: command,
            workingDirectory: repoPath?.path,
            onFormattedOutput: onOutput
        )
        return output.value
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

private final class OutputAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    var content: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += text
    }
}
