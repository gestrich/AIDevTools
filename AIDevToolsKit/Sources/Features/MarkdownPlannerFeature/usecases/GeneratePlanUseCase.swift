import AIOutputSDK
import Foundation
import RepositorySDK

public struct GeneratePlanUseCase: Sendable {

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
        let architectureDocs = repo.architectureDocs ?? []
        let verificationCommands = repo.verification?.commands ?? []

        var repoContextLines = [
            "Repository: \(repo.id.uuidString)",
            "Path: \(repo.path.path())",
            "Description: \(repo.description ?? repo.name)",
            "Skills: \(skills.joined(separator: ", "))",
            "Architecture docs: \(architectureDocs.joined(separator: ", "))",
            "Verification commands: \(verificationCommands.joined(separator: ", "))",
        ]
        if let pr = repo.pullRequest {
            repoContextLines.append("PR base branch: \(pr.baseBranch)")
            repoContextLines.append("Branch naming: \(pr.branchNamingConvention)")
        }
        if let githubUser = repo.githubUser {
            repoContextLines.append("GitHub user: \(githubUser) (switch with `gh auth switch -u \(githubUser)` before any gh commands)")
        }
        let repoContext = repoContextLines.joined(separator: "\n")

        let skillsList = skills.joined(separator: ", ")
        let archDocsList = architectureDocs.joined(separator: ", ")

        let prompt = """
        You are generating a phased implementation plan document. You are ONLY generating the plan skeleton — do NOT execute, explore, or implement anything.

        Request: "\(interpretedRequest)"

        Repository context:
        \(repoContext)

        Generate a markdown plan document with EXACTLY this structure:

        1. A title (## heading) based on the request
        2. A "Background" section briefly describing what needs to be done
        3. Exactly three phases, all unchecked:

        ## - [ ] Phase 1: Interpret the Request
        When executed, this phase will explore the codebase and recent commits to understand what the request is asking for. It will find the relevant code, files, and areas. This phase is purely about understanding — no implementation planning yet. Use recent commits and codebase context to infer intent. Document findings underneath this phase heading.

        ## - [ ] Phase 2: Gather Architectural Guidance
        When executed, this phase will look at the repository's skills (\(skillsList)) and architecture docs (\(archDocsList)) to identify which documentation and architectural guidelines are relevant to this request. It will read and summarize the key constraints. Document findings underneath this phase heading.

        ## - [ ] Phase 3: Plan the Implementation
        When executed, this phase will use insights from Phases 1 and 2 to create concrete implementation steps. It will append new phases (Phase 4 through N) to this document, each with: what to implement, which files to modify, which architectural documents to reference, and acceptance criteria. It will also append a Testing/Verification phase and a Create Pull Request phase at the end. The Create Pull Request phase MUST always use `gh pr create --draft` (all PRs are drafts).\(repo.githubUser.map { " Before any `gh` commands, run `gh auth switch -u \($0)`." } ?? "") This phase is responsible for generating the remaining phases dynamically.
        \(architectureJSONInstruction(architectureDocs: architectureDocs))

        CRITICAL scope and sizing rules for Phase 3:
        - Stay focused on exactly what was requested. Do not expand scope, refactor surrounding code, or make unrelated improvements.
        - Follow a "do no harm" principle: do not restructure or rewrite existing code that already works. New code should follow good architecture and introduce new paradigms where needed, but existing code should be left alone unless it is directly required by the request.
        - Scale the number of implementation phases to match the size of the request. A small change may need only 1-2 implementation phases. A large feature may need up to 10. Never exceed 10 implementation phases (excluding the Testing/Verification and Create Pull Request phases).

        No Phase 4+ should be included — Phase 3 will generate them when executed.

        All phases must be unchecked (- [ ]). None are completed at this stage.

        Also generate a filename for this plan (kebab-case, no extension, descriptive of the request).

        Return the full markdown content as planContent and the filename as filename.
        """

        let schema = """
        {"type":"object","properties":{"planContent":{"type":"string","description":"The full markdown plan document content"},"filename":{"type":"string","description":"Kebab-case filename without extension"}},"required":["planContent","filename"]}
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

    private func architectureJSONInstruction(architectureDocs: [String]) -> String {
        guard !architectureDocs.isEmpty else { return "" }

        return """
        Additionally, after generating implementation phases, Phase 3 must also produce an architecture diagram JSON file.

        Read the repository's ARCHITECTURE.md (listed in architecture docs: \(architectureDocs.joined(separator: ", "))).
        For every file planned to be added, modified, or deleted across all implementation phases, map it to the appropriate module and layer from ARCHITECTURE.md.

        Write the JSON to the same directory as this plan file, named: {this-plan-filename-without-extension}-architecture.json (e.g., if this plan is my-feature.md, write my-feature-architecture.json).

        The JSON must conform to this schema:
        {
          "layers": [
            {
              "name": "LayerName",
              "dependsOn": ["OtherLayer"],
              "modules": [
                {
                  "name": "ModuleName",
                  "changes": [
                    {
                      "file": "relative/path/from/repo/root",
                      "action": "add|modify|delete",
                      "summary": "One-line description",
                      "phase": 4
                    }
                  ]
                }
              ]
            }
          ]
        }

        Include ALL layers and modules from ARCHITECTURE.md, even those with no changes (use empty changes array).
        The layers array must be ordered top-to-bottom (highest layer first).
        Map files to modules using directory structure conventions (e.g., Sources/{Layer}/{Module}/).
        Root-level files like Package.swift that don't belong to a module should be omitted.
        """
    }

    private func writePlan(_ plan: GeneratedPlan, to proposedDirectory: URL) throws -> URL {
        let filename = plan.filename.hasSuffix(".md")
            ? plan.filename
            : plan.filename + ".md"

        let fm = FileManager.default
        do {
            if !fm.fileExists(atPath: proposedDirectory.path) {
                try fm.createDirectory(at: proposedDirectory, withIntermediateDirectories: true)
            }
        } catch {
            throw GenerateError.writeError("Could not create directory: \(error.localizedDescription)")
        }

        let planURL = proposedDirectory.appendingPathComponent(filename)
        do {
            try plan.planContent.write(to: planURL, atomically: true, encoding: .utf8)
        } catch {
            throw GenerateError.writeError("Could not write plan file: \(error.localizedDescription)")
        }

        return planURL
    }
}
