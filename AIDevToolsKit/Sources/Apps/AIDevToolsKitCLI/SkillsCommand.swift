import ArgumentParser
import DataPathsService
import Foundation
import RepositorySDK
import SettingsService
import SkillBrowserFeature
import SkillScannerSDK

struct SkillsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "List skills for a repository"
    )

    @Option(help: "Data directory path (default: ~/Desktop/AIDevTools)")
    var dataPath: String?

    @Argument(help: "Repository path or UUID of a configured repository")
    var repo: String

    func run() async throws {
        let settings = try ReposCommand.makeSettingsService(dataPath: dataPath)
        let repoInfo = try resolveRepo(store: settings.repositoryStore)
        let skills = try await LoadSkillsUseCase().run(options: repoInfo)
        if skills.isEmpty {
            print("No skills found at \(repoInfo.path.path())")
            return
        }
        for skill in skills {
            print("\(skill.name) (\(skill.source.rawValue))")
        }
    }

    private func resolveRepo(store: RepositoryStore) throws -> RepositoryConfiguration {
        if let uuid = UUID(uuidString: repo) {
            let repos = try LoadRepositoriesUseCase(store: store).run()
            if let match = repos.first(where: { $0.id == uuid }) {
                return match
            }
        }
        let url = URL(filePath: repo, relativeTo: URL(filePath: FileManager.default.currentDirectoryPath))
        return RepositoryConfiguration(path: url)
    }
}
