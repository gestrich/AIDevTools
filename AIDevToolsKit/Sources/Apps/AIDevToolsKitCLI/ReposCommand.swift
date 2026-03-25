import ArgumentParser
import DataPathsService
import EvalService
import Foundation
import PlanRunnerService
import RepositorySDK
import SkillBrowserFeature

struct ReposCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "repos",
        abstract: "Manage repository configurations",
        subcommands: [AddRepo.self, ListRepos.self, RemoveRepo.self, UpdateRepo.self]
    )

    @Option(help: "Data directory path (overrides app settings)")
    var dataPath: String?

    static func makeDataPathsService(dataPath: String?) throws -> DataPathsService {
        try .fromCLI(dataPath: dataPath)
    }

    static func makeStore(_ service: DataPathsService) throws -> RepositoryStore {
        RepositoryStore(repositoriesFile: try service.path(for: .repositories).appending(path: "repositories.json"))
    }

    static func makeEvalSettingsStore(_ service: DataPathsService) throws -> EvalRepoSettingsStore {
        EvalRepoSettingsStore(filePath: try service.path(for: .evalSettings).appending(path: "eval-settings.json"))
    }

    static func makePlanSettingsStore(_ service: DataPathsService) throws -> PlanRepoSettingsStore {
        PlanRepoSettingsStore(filePath: try service.path(for: .planSettings).appending(path: "plan-settings.json"))
    }
}

struct ListRepos: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List configured repositories"
    )

    @OptionGroup var dataPathOptions: ReposCommand

    func run() throws {
        let service = try ReposCommand.makeDataPathsService(dataPath: dataPathOptions.dataPath)
        let store = try ReposCommand.makeStore(service)
        let evalSettingsStore = try ReposCommand.makeEvalSettingsStore(service)
        let planSettingsStore = try ReposCommand.makePlanSettingsStore(service)
        let repos = try LoadRepositoriesUseCase(store: store).run()
        if repos.isEmpty {
            print("No repositories configured.")
            return
        }
        for repo in repos {
            let evalSettings = try evalSettingsStore.settings(forRepoId: repo.id)
            let planSettings = try planSettingsStore.settings(forRepoId: repo.id)
            let casesInfo = evalSettings.map { "  cases-dir=\($0.casesDirectory)" } ?? ""
            let proposedInfo = planSettings?.proposedDirectory.map { "  proposed-dir=\($0)" } ?? ""
            let completedInfo = planSettings?.completedDirectory.map { "  completed-dir=\($0)" } ?? ""
            print("\(repo.id)  \(repo.name)  \(repo.path.path())\(casesInfo)\(proposedInfo)\(completedInfo)")
        }
    }
}

struct AddRepo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a repository"
    )

    @OptionGroup var dataPathOptions: ReposCommand

    @Argument(help: "Path to the repository")
    var path: String

    @Option(help: "Custom display name (defaults to directory name)")
    var name: String?

    @Option(help: "Cases directory path (absolute or relative to repo)")
    var casesDir: String?

    @Option(help: "Completed plans directory path (absolute or relative to repo, default: docs/completed)")
    var completedDir: String?

    @Option(help: "Proposed plans directory path (absolute or relative to repo, default: docs/proposed)")
    var proposedDir: String?

    func run() throws {
        let url = URL(filePath: path, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath))
        let service = try ReposCommand.makeDataPathsService(dataPath: dataPathOptions.dataPath)
        let store = try ReposCommand.makeStore(service)
        let repo = try AddRepositoryUseCase(store: store).run(path: url, name: name)
        if let casesDir {
            let evalSettingsStore = try ReposCommand.makeEvalSettingsStore(service)
            try evalSettingsStore.update(repoId: repo.id, casesDirectory: casesDir)
        }
        if completedDir != nil || proposedDir != nil {
            let planSettingsStore = try ReposCommand.makePlanSettingsStore(service)
            try planSettingsStore.update(repoId: repo.id, proposedDirectory: proposedDir, completedDirectory: completedDir)
        }
        print("Added repository: \(repo.name) (\(repo.id))")
    }
}

struct RemoveRepo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove",
        abstract: "Remove a repository by ID"
    )

    @OptionGroup var dataPathOptions: ReposCommand

    @Argument(help: "UUID of the repository to remove")
    var id: String

    func run() throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        let service = try ReposCommand.makeDataPathsService(dataPath: dataPathOptions.dataPath)
        let store = try ReposCommand.makeStore(service)
        let evalSettingsStore = try ReposCommand.makeEvalSettingsStore(service)
        let planSettingsStore = try ReposCommand.makePlanSettingsStore(service)
        try RemoveRepositoryUseCase(store: store).run(id: uuid)
        try evalSettingsStore.remove(repoId: uuid)
        try planSettingsStore.remove(repoId: uuid)
        print("Removed repository: \(uuid)")
    }
}

struct UpdateRepo: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Update a repository configuration"
    )

    @OptionGroup var dataPathOptions: ReposCommand

    @Argument(help: "UUID of the repository to update")
    var id: String

    @Option(help: "New repository path")
    var path: String?

    @Option(help: "New display name")
    var name: String?

    @Option(help: "New cases directory path (absolute or relative to repo)")
    var casesDir: String?

    @Option(help: "New completed plans directory path (absolute or relative to repo, default: docs/completed)")
    var completedDir: String?

    @Option(help: "New proposed plans directory path (absolute or relative to repo, default: docs/proposed)")
    var proposedDir: String?

    @Option(help: "Description of the repository")
    var description: String?

    @Option(help: "GitHub username for gh CLI auth switching")
    var githubUser: String?

    @Option(help: "Current focus area for the repository")
    var recentFocus: String?

    @Option(parsing: .upToNextOption, help: "Skills (space-separated list)")
    var skills: [String] = []

    @Option(parsing: .upToNextOption, help: "Architecture doc paths relative to repo root (space-separated)")
    var architectureDocs: [String] = []

    @Option(parsing: .upToNextOption, help: "Verification commands (space-separated)")
    var verificationCommands: [String] = []

    @Option(help: "Verification notes")
    var verificationNotes: String?

    @Option(help: "PR base branch")
    var prBaseBranch: String?

    @Option(help: "PR branch naming convention")
    var prBranchNaming: String?

    @Option(help: "PR template path")
    var prTemplate: String?

    @Option(help: "PR notes")
    var prNotes: String?

    func run() throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        let service = try ReposCommand.makeDataPathsService(dataPath: dataPathOptions.dataPath)
        let store = try ReposCommand.makeStore(service)
        let repos = try LoadRepositoriesUseCase(store: store).run()
        guard var repo = repos.first(where: { $0.id == uuid }) else {
            throw ValidationError("Repository not found: \(id)")
        }

        let cwd = URL(filePath: FileManager.default.currentDirectoryPath)
        if let path {
            repo = RepositoryInfo(
                id: repo.id,
                path: URL(filePath: path, relativeTo: cwd),
                name: name ?? repo.name,
                description: repo.description,
                githubUser: repo.githubUser,
                recentFocus: repo.recentFocus,
                skills: repo.skills,
                architectureDocs: repo.architectureDocs,
                verification: repo.verification,
                pullRequest: repo.pullRequest
            )
        }
        if let name { repo = RepositoryInfo(id: repo.id, path: repo.path, name: name, description: repo.description, githubUser: repo.githubUser, recentFocus: repo.recentFocus, skills: repo.skills, architectureDocs: repo.architectureDocs, verification: repo.verification, pullRequest: repo.pullRequest) }
        if let description { repo.description = description }
        if let githubUser { repo.githubUser = githubUser }
        if let recentFocus { repo.recentFocus = recentFocus }
        if !skills.isEmpty { repo.skills = skills }
        if !architectureDocs.isEmpty { repo.architectureDocs = architectureDocs }
        if !verificationCommands.isEmpty || verificationNotes != nil {
            repo.verification = Verification(
                commands: verificationCommands.isEmpty ? (repo.verification?.commands ?? []) : verificationCommands,
                notes: verificationNotes ?? repo.verification?.notes
            )
        }
        if prBaseBranch != nil || prBranchNaming != nil || prTemplate != nil || prNotes != nil {
            repo.pullRequest = PullRequestConfig(
                baseBranch: prBaseBranch ?? repo.pullRequest?.baseBranch ?? "main",
                branchNamingConvention: prBranchNaming ?? repo.pullRequest?.branchNamingConvention ?? "feature/description",
                template: prTemplate ?? repo.pullRequest?.template,
                notes: prNotes ?? repo.pullRequest?.notes
            )
        }

        try UpdateRepositoryUseCase(store: store).run(repo)

        if let casesDir {
            let evalSettingsStore = try ReposCommand.makeEvalSettingsStore(service)
            try evalSettingsStore.update(repoId: uuid, casesDirectory: casesDir)
        }

        if completedDir != nil || proposedDir != nil {
            let planSettingsStore = try ReposCommand.makePlanSettingsStore(service)
            try planSettingsStore.update(repoId: uuid, proposedDirectory: proposedDir, completedDirectory: completedDir)
        }

        print("Updated repository: \(repo.name) (\(repo.id))")
    }
}
