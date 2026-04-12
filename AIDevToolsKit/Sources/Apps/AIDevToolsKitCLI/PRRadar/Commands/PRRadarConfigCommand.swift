import ArgumentParser
import DataPathsService
import Foundation
import RepositorySDK
import SettingsService

struct PRRadarConfigCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "config",
        abstract: "Manage PRRadar configurations",
        subcommands: [PRRadarConfigAddCommand.self, PRRadarConfigListCommand.self]
    )
}

struct PRRadarConfigAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a PRRadar configuration for a repository"
    )

    @Argument(help: "Configuration name")
    var name: String

    @Option(name: .long, help: "Path to the repository being reviewed")
    var repoPath: String

    @Option(name: .long, help: "Path to the rules directory")
    var rulesDir: String

    @Option(name: .long, help: "GitHub credential account name")
    var githubAccount: String = ""

    @Option(name: .long, help: "Default base branch (default: main)")
    var defaultBaseBranch: String = "main"

    @Option(name: .long, help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() async throws {
        let dataPathsService = try DataPathsService.fromCLI(dataPath: dataPath)
        let settingsService = try SettingsService(dataPathsService: dataPathsService)

        let repoURL = URL(filePath: repoPath)
        let ruleDirName = URL(filePath: rulesDir).lastPathComponent
        let rulePath = RulePath(name: ruleDirName, path: rulesDir, isDefault: true)
        let prradarSettings = PRRadarRepoSettings(
            rulePaths: [rulePath],
            diffSource: .githubAPI
        )
        var repo = RepositoryConfiguration(path: repoURL, name: name)
        if !githubAccount.isEmpty {
            repo.credentialAccount = githubAccount
        }
        repo.prradar = prradarSettings
        repo.pullRequest = PullRequestConfig(
            baseBranch: defaultBaseBranch,
            branchNamingConvention: "feature/description"
        )

        try settingsService.addRepository(repo)
        print("Added PRRadar configuration: \(name)")
    }
}

struct PRRadarConfigListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List saved PRRadar configurations"
    )

    @Option(name: .long, help: "Data directory path (overrides app settings)")
    var dataPath: String?

    func run() async throws {
        let dataPathsService = try DataPathsService.fromCLI(dataPath: dataPath)
        let settingsService = try SettingsService(dataPathsService: dataPathsService)
        let repos = try settingsService.loadRepositories()
        let withPRRadar = repos.filter { $0.prradar != nil }

        if withPRRadar.isEmpty {
            print("No PRRadar configurations saved.")
            return
        }

        print("Saved PRRadar configurations:\n")
        for repo in withPRRadar {
            print("  \(repo.name)  (\(repo.id))")
            print("    repo-path: \(repo.path.path())")
            if let prradar = repo.prradar {
                for rp in prradar.rulePaths {
                    print("    rules-dir: \(rp.path)\(rp.isDefault ? " (default)" : "")")
                }
                print("    diff-source: \(prradar.diffSource.rawValue)")
            }
        }
    }
}
