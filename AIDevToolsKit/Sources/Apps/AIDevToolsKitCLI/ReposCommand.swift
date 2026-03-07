import ArgumentParser
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

    @Option(help: "Data directory path (default: ~/Desktop/ai-dev-tools)")
    var dataPath: String?

    static func makeStore(dataPath: String?) -> RepositoryStore {
        .fromCLI(dataPath: dataPath)
    }

    static func makeEvalSettingsStore(dataPath: String?) -> EvalRepoSettingsStore {
        .fromCLI(dataPath: dataPath)
    }

    static func makePlanSettingsStore(dataPath: String?) -> PlanRepoSettingsStore {
        .fromCLI(dataPath: dataPath)
    }
}

struct ListRepos: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List configured repositories"
    )

    @OptionGroup var parent: ReposCommand

    func run() throws {
        let store = ReposCommand.makeStore(dataPath: parent.dataPath)
        let evalSettingsStore = ReposCommand.makeEvalSettingsStore(dataPath: parent.dataPath)
        let planSettingsStore = ReposCommand.makePlanSettingsStore(dataPath: parent.dataPath)
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

    @OptionGroup var parent: ReposCommand

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
        let store = ReposCommand.makeStore(dataPath: parent.dataPath)
        let repo = try AddRepositoryUseCase(store: store).run(path: url, name: name)
        if let casesDir {
            let evalSettingsStore = ReposCommand.makeEvalSettingsStore(dataPath: parent.dataPath)
            try evalSettingsStore.update(repoId: repo.id, casesDirectory: casesDir)
        }
        if completedDir != nil || proposedDir != nil {
            let planSettingsStore = ReposCommand.makePlanSettingsStore(dataPath: parent.dataPath)
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

    @OptionGroup var parent: ReposCommand

    @Argument(help: "UUID of the repository to remove")
    var id: String

    func run() throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        let store = ReposCommand.makeStore(dataPath: parent.dataPath)
        let evalSettingsStore = ReposCommand.makeEvalSettingsStore(dataPath: parent.dataPath)
        let planSettingsStore = ReposCommand.makePlanSettingsStore(dataPath: parent.dataPath)
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

    @OptionGroup var parent: ReposCommand

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

    func run() throws {
        guard let uuid = UUID(uuidString: id) else {
            throw ValidationError("Invalid UUID: \(id)")
        }
        let store = ReposCommand.makeStore(dataPath: parent.dataPath)
        let repos = try LoadRepositoriesUseCase(store: store).run()
        guard var repo = repos.first(where: { $0.id == uuid }) else {
            throw ValidationError("Repository not found: \(id)")
        }

        let cwd = URL(filePath: FileManager.default.currentDirectoryPath)
        if let path {
            let newPath = URL(filePath: path, relativeTo: cwd)
            repo = RepositoryInfo(id: repo.id, path: newPath, name: name ?? newPath.lastPathComponent)
        } else if let name {
            repo = RepositoryInfo(id: repo.id, path: repo.path, name: name)
        }

        try UpdateRepositoryUseCase(store: store).run(repo)

        if let casesDir {
            let evalSettingsStore = ReposCommand.makeEvalSettingsStore(dataPath: parent.dataPath)
            try evalSettingsStore.update(repoId: uuid, casesDirectory: casesDir)
        }

        if completedDir != nil || proposedDir != nil {
            let planSettingsStore = ReposCommand.makePlanSettingsStore(dataPath: parent.dataPath)
            try planSettingsStore.update(repoId: uuid, proposedDirectory: proposedDir, completedDirectory: completedDir)
        }

        print("Updated repository: \(repo.name) (\(repo.id))")
    }
}
