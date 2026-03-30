import AIOutputSDK
import Foundation
import RepositorySDK
import UseCaseSDK

public struct GeneratePlanUseCase: UseCase {

    public struct Options: Sendable {
        public let prompt: String
        public let repositories: [RepositoryInfo]
        public let selectedRepository: RepositoryInfo?

        public init(
            prompt: String,
            repositories: [RepositoryInfo],
            selectedRepository: RepositoryInfo? = nil
        ) {
            self.prompt = prompt
            self.repositories = repositories
            self.selectedRepository = selectedRepository
        }
    }

    public struct Result: Sendable {
        public let planURL: URL
        public let repository: RepositoryInfo
        public let repoMatch: RepoMatch
        public let plan: GeneratedPlan

        public init(planURL: URL, repository: RepositoryInfo, repoMatch: RepoMatch, plan: GeneratedPlan) {
            self.planURL = planURL
            self.repository = repository
            self.repoMatch = repoMatch
            self.plan = plan
        }
    }

    public enum Progress: Sendable {
        case matchingRepo
        case matchedRepo(repoId: String, interpretedRequest: String)
        case generatingPlan
        case generatedPlan(filename: String)
        case writingPlan
        case completed(planURL: URL, repository: RepositoryInfo)
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

    private let client: any AIClient
    private let resolveProposedDirectory: @Sendable (RepositoryInfo) throws -> URL

    public init(
        client: any AIClient,
        resolveProposedDirectory: @escaping @Sendable (RepositoryInfo) throws -> URL
    ) {
        self.client = client
        self.resolveProposedDirectory = resolveProposedDirectory
    }

    public func run(
        _ options: Options,
        onProgress: (@Sendable (Progress) -> Void)? = nil
    ) async throws -> Result {
        let repo: RepositoryInfo
        let repoMatch: RepoMatch

        if let selected = options.selectedRepository {
            repo = selected
            repoMatch = RepoMatch(repoId: selected.id.uuidString, interpretedRequest: options.prompt)
            onProgress?(.matchedRepo(repoId: repoMatch.repoId, interpretedRequest: repoMatch.interpretedRequest))
        } else {
            onProgress?(.matchingRepo)
            repoMatch = try await matchRepo(
                prompt: options.prompt,
                repositories: options.repositories
            )
            onProgress?(.matchedRepo(repoId: repoMatch.repoId, interpretedRequest: repoMatch.interpretedRequest))

            guard let repoUUID = UUID(uuidString: repoMatch.repoId),
                  let matched = options.repositories.first(where: { $0.id == repoUUID }) else {
                throw GenerateError.repoNotFound(repoMatch.repoId)
            }
            repo = matched
        }

        onProgress?(.generatingPlan)
        let plan: GeneratedPlan = try await generatePlan(
            interpretedRequest: repoMatch.interpretedRequest,
            repo: repo
        )
        onProgress?(.generatedPlan(filename: plan.filename))

        onProgress?(.writingPlan)
        let proposedDir = try resolveProposedDirectory(repo)
        let planURL = try writePlan(plan, to: proposedDir)
        onProgress?(.completed(planURL: planURL, repository: repo))

        return Result(
            planURL: planURL,
            repository: repo,
            repoMatch: repoMatch,
            plan: plan
        )
    }

    // MARK: - Private

    private func matchRepo(prompt: String, repositories: [RepositoryInfo]) async throws -> RepoMatch {
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

    private func generatePlan(interpretedRequest: String, repo: RepositoryInfo) async throws -> GeneratedPlan {
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
}
