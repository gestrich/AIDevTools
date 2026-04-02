import AIOutputSDK
import CredentialService
import Foundation
import GitSDK
import Logging
import PipelineSDK
import RepositorySDK

public struct MarkdownPlannerService: Sendable {

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
        let repo: RepositoryConfiguration
        let repoMatch: RepoMatch

        if let selected = options.selectedRepository {
            repo = selected
            repoMatch = RepoMatch(repoId: selected.id.uuidString, interpretedRequest: options.prompt)
            onProgress?(.matchedRepo(repoId: repoMatch.repoId, interpretedRequest: repoMatch.interpretedRequest))
        } else {
            onProgress?(.matchingRepo)
            repoMatch = try await matchRepo(prompt: options.prompt, repositories: options.repositories)
            onProgress?(.matchedRepo(repoId: repoMatch.repoId, interpretedRequest: repoMatch.interpretedRequest))

            guard let repoUUID = UUID(uuidString: repoMatch.repoId),
                  let matched = options.repositories.first(where: { $0.id == repoUUID }) else {
                throw GenerateError.repoNotFound(repoMatch.repoId)
            }
            repo = matched
        }

        onProgress?(.generatingPlan)
        let plan = try await generatePlan(interpretedRequest: repoMatch.interpretedRequest, repo: repo)
        onProgress?(.generatedPlan(filename: plan.filename))

        onProgress?(.writingPlan)
        let proposedDir = try resolveProposedDirectory(repo)
        let planURL = try writePlan(plan, to: proposedDir)
        onProgress?(.completed(planURL: planURL, repository: repo))

        return GenerateResult(planURL: planURL, repository: repo, repoMatch: repoMatch, plan: plan)
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

        let pipelineSource = MarkdownPipelineSource(fileURL: options.planPath, format: .phase)
        onProgress?(.fetchingStatus)
        var statusResponse = try await loadPhaseStatus(from: pipelineSource)
        var phases = statusResponse.phases
        var nextIndex = statusResponse.nextPhaseIndex

        onProgress?(.phaseOverview(phases: phases))

        if nextIndex == -1 {
            let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
            onProgress?(.allCompleted(phasesExecuted: 0, totalSeconds: totalSeconds))
            return ExecuteResult(phasesExecuted: 0, totalPhases: phases.count, allCompleted: true, totalSeconds: totalSeconds)
        }

        var phasesExecuted = 0

        while nextIndex != -1 {
            let elapsed = Date().timeIntervalSince(scriptStart)
            if Int(elapsed) >= maxRuntimeSeconds {
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
                writePhaseLog(output: await outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
                logger.error("Phase \(nextIndex + 1) failed: \(error.localizedDescription)", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)"
                ])
                onProgress?(.phaseFailed(index: nextIndex, description: phase.description, error: error.localizedDescription))
                onProgress?(.phaseCompleted(index: nextIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
                throw ExecuteError.phaseFailed(index: nextIndex, description: phase.description, underlyingError: error.localizedDescription)
            }

            let phaseElapsed = Int(Date().timeIntervalSince(phaseStart))
            let totalElapsed = Int(Date().timeIntervalSince(scriptStart))

            if !phaseResult.success {
                writePhaseLog(output: await outputAccumulator.content, phaseIndex: nextIndex, logDirectory: logDir)
                let reason = "Phase reported failure"
                logger.error("Phase \(nextIndex + 1) failed: \(reason)", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)"
                ])
                onProgress?(.phaseFailed(index: nextIndex, description: phase.description, error: reason))
                onProgress?(.phaseCompleted(index: nextIndex, elapsedSeconds: phaseElapsed, totalElapsedSeconds: totalElapsed))
                throw ExecuteError.phaseFailed(index: nextIndex, description: phase.description, underlyingError: reason)
            }

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
                return ExecuteResult(phasesExecuted: 1, totalPhases: phases.count, allCompleted: false, totalSeconds: totalSeconds)
            }

            if options.stopAfterArchitectureDiagram && architectureDiagramExists(planPath: options.planPath) {
                let totalSeconds = Int(Date().timeIntervalSince(scriptStart))
                logger.info("Stopping after architecture diagram detected", metadata: [
                    "plan": "\(options.planPath.lastPathComponent)"
                ])
                return ExecuteResult(
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

        return ExecuteResult(
            phasesExecuted: phasesExecuted,
            totalPhases: phases.count,
            allCompleted: allDone,
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

    // MARK: - Private: repo matching

    private func matchRepo(prompt: String, repositories: [RepositoryConfiguration]) async throws -> RepoMatch {
        let repoList = repositories.map { repo in
            var entry = "- id: \(repo.id.uuidString) | description: \(repo.description ?? repo.name)"
            if let focus = repo.recentFocus {
                entry += " | recent focus: \(focus)"
            }
            return entry
        }.joined(separator: "\n")

        let matchPrompt = """
        You are helping match a development request to the correct repository.

        Use the repository descriptions and recent focus areas to infer the best match.

        Request: "\(prompt)"

        Available repositories:
        \(repoList)

        You MUST select one of the listed repositories. Do not reference or suggest any repository not in this list.

        Return the best matching repository ID and your interpretation of what the request is asking for.
        """

        let schema = """
        {"type":"object","properties":{"repoId":{"type":"string","description":"The id of the matched repository"},"interpretedRequest":{"type":"string","description":"The interpreted version of the request"}},"required":["repoId","interpretedRequest"]}
        """

        let output = try await client.runStructured(
            RepoMatch.self,
            prompt: matchPrompt,
            jsonSchema: schema,
            options: AIClientOptions(),
            onOutput: nil
        )
        return output.value
    }

    // MARK: - Private: plan generation

    private func generatePlan(interpretedRequest: String, repo: RepositoryConfiguration) async throws -> GeneratedPlan {
        let skills = repo.skills ?? []
        let verificationCommands = repo.verification?.commands ?? []

        var repoContextLines = [
            "Repository: \(repo.id.uuidString)",
            "Path: \(repo.path.path())",
            "Description: \(repo.description ?? repo.name)",
            "Skills: \(skills.joined(separator: ", "))",
            "Verification commands: \(verificationCommands.joined(separator: ", "))",
        ]
        if let pr = repo.pullRequest {
            repoContextLines.append("PR base branch: \(pr.baseBranch)")
            repoContextLines.append("Branch naming: \(pr.branchNamingConvention)")
        }
        if let credentialAccount = repo.credentialAccount {
            repoContextLines.append("Credential account: \(credentialAccount) (GH_TOKEN injected automatically)")
        }
        let repoContext = repoContextLines.joined(separator: "\n")

        let projectInstructions = readProjectInstructions(at: repo.path)

        let prompt = """
        You are generating a complete, detailed phased implementation plan. You are ONLY generating the plan — do NOT execute, explore, or implement anything.

        Request: "\(interpretedRequest)"

        Repository context:
        \(repoContext)
        \(projectInstructions.map { "\nCLAUDE.md contents:\n\($0)" } ?? "")

        Generate a markdown plan document with this structure:

        1. **Relevant Skills** table at the top — only skills relevant to the task, discovered from the CLAUDE.md content above. Format:
           ```
           ## Relevant Skills

           | Skill | Description |
           |-------|-------------|
           | `skill-name` | Brief description of why it's relevant |
           ```

        2. **Background** section — why we're making changes, user requirements, context

        3. **All implementation phases** (Phase 1 through N, ≤10 total), each as:
           ```
           ## - [ ] Phase N: Short Description

           **Skills to read**: `skill-a`, `skill-b`

           Detailed description of what to implement. Include:
           - Specific tasks and files to modify
           - Technical considerations
           - Expected outcome
           ```
           The "Skills to read" line tells the executor which skills to read before implementing that phase. Only include skills genuinely relevant to that phase. Omit the line if no skills apply.

        4. **Final phase is always Validation** — prefer automated testing (running test suites, build verification) over manual verification. Include specific commands to run.

        CRITICAL scope and sizing rules:
        - Stay focused on exactly what was requested. Do not expand scope, refactor surrounding code, or make unrelated improvements.
        - Follow a "do no harm" principle: do not restructure or rewrite existing code that already works.
        - Scale the number of phases to match the size of the request. A small change may need only 1-2 phases. A large feature may need up to 10. Never exceed 10 phases total.
        - Every phase must be actionable and concrete — no "explore" or "gather context" phases.

        All phases must be unchecked (## - [ ]). None are completed at this stage.

        Also generate a short kebab-case description for the filename (e.g., "add-voice-commands", "fix-auth-timeout"). Do not include dates or extensions.

        Return the full markdown content as planContent and the description as filename.
        """

        let schema = """
        {"type":"object","properties":{"planContent":{"type":"string","description":"The full markdown plan document content"},"filename":{"type":"string","description":"Short kebab-case description without date prefix or extension"}},"required":["planContent","filename"]}
        """

        let options = AIClientOptions(
            dangerouslySkipPermissions: true,
            workingDirectory: repo.path.path()
        )

        let output = try await client.runStructured(
            GeneratedPlan.self,
            prompt: prompt,
            jsonSchema: schema,
            options: options,
            onOutput: nil
        )
        return output.value
    }

    private func readProjectInstructions(at repoPath: URL) -> String? {
        let instructionsURL = repoPath.appendingPathComponent("CLAUDE.md")
        return try? String(contentsOf: instructionsURL, encoding: .utf8)
    }

    private func writePlan(_ plan: GeneratedPlan, to proposedDirectory: URL) throws -> URL {
        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: proposedDirectory.path) {
                try fm.createDirectory(at: proposedDirectory, withIntermediateDirectories: true)
            }
        } catch {
            throw GenerateError.writeError("Could not create directory: \(error.localizedDescription)")
        }

        let filename = buildFilename(description: plan.filename, in: proposedDirectory)
        let planURL = proposedDirectory.appendingPathComponent(filename)
        do {
            try plan.planContent.write(to: planURL, atomically: true, encoding: .utf8)
        } catch {
            throw GenerateError.writeError("Could not write plan file: \(error.localizedDescription)")
        }

        return planURL
    }

    private func buildFilename(description: String, in directory: URL) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let datePrefix = formatter.string(from: Date())

        let cleanDescription = description
            .replacingOccurrences(of: ".md", with: "")
            .trimmingCharacters(in: .whitespaces)

        let existingFiles = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let todayFiles = existingFiles.filter { $0.hasPrefix(datePrefix) }

        let alphaIndex: String
        if todayFiles.isEmpty {
            alphaIndex = "a"
        } else {
            let usedLetters = todayFiles.compactMap { filename -> Character? in
                let afterDate = filename.dropFirst(datePrefix.count)
                guard afterDate.hasPrefix("-"), afterDate.count > 1 else { return nil }
                let letter = afterDate[afterDate.index(after: afterDate.startIndex)]
                guard letter.isLetter, afterDate.count > 2,
                      afterDate[afterDate.index(afterDate.startIndex, offsetBy: 2)] == "-" else { return nil }
                return letter
            }
            let maxLetter = usedLetters.max() ?? Character("a")
            let nextScalar = Unicode.Scalar(maxLetter.asciiValue! + 1)
            alphaIndex = String(nextScalar)
        }

        return "\(datePrefix)-\(alphaIndex)-\(cleanDescription).md"
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

        let skillsToRead = ExecutePlanUseCase.parseSkillsToRead(planPath: planPath, phaseIndex: phaseIndex)
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

    // MARK: - Private: architecture diagram detection

    private func architectureDiagramExists(planPath: URL) -> Bool {
        let planName = planPath.deletingPathExtension().lastPathComponent
        let architectureURL = planPath
            .deletingLastPathComponent()
            .appendingPathComponent("\(planName)-architecture.json")
        return FileManager.default.fileExists(atPath: architectureURL.path)
    }

    // MARK: - Private: phase status

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
