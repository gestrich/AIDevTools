import DataPathsService
import Foundation
import PRRadarConfigService
import RepositorySDK
import SkillBrowserFeature
import SkillScannerSDK

@MainActor @Observable
final class WorkspaceModel {

    enum State {
        case idle
        case loading
        case loaded
        case loadingSkills
        case error(Error)
    }

    private(set) var repositories: [RepositoryConfiguration] = []
    private(set) var selectedRepository: RepositoryConfiguration?
    private(set) var skills: [SkillInfo] = []
    private(set) var state: State = .idle

    private let dataPathsService: DataPathsService
    private let repositoryStore: RepositoryStore
    private let loadRepositories: LoadRepositoriesUseCase
    private let loadSkills: LoadSkillsUseCase
    private let configureNewRepository: ConfigureNewRepositoryUseCase
    private let removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase
    private let updateRepository: UpdateRepositoryUseCase
    private let worktreeModel: WorktreeModel?

    init(
        dataPathsService: DataPathsService,
        repositoryStore: RepositoryStore,
        loadRepositories: LoadRepositoriesUseCase,
        loadSkills: LoadSkillsUseCase,
        configureNewRepository: ConfigureNewRepositoryUseCase,
        removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase,
        updateRepository: UpdateRepositoryUseCase,
        worktreeModel: WorktreeModel? = nil
    ) {
        self.dataPathsService = dataPathsService
        self.repositoryStore = repositoryStore
        self.loadRepositories = loadRepositories
        self.loadSkills = loadSkills
        self.configureNewRepository = configureNewRepository
        self.removeRepositoryWithSettings = removeRepositoryWithSettings
        self.updateRepository = updateRepository
        self.worktreeModel = worktreeModel
    }

    func evalConfig(for repo: RepositoryConfiguration) -> RepositoryEvalConfig? {
        guard let settings = repo.eval else { return nil }
        guard let outputDirectory = try? dataPathsService.path(for: .evalsOutput(repo.name)) else { return nil }
        return RepositoryEvalConfig(
            casesDirectory: settings.resolvedCasesDirectory(repoPath: repo.path),
            outputDirectory: outputDirectory,
            repoRoot: repo.path
        )
    }

    func casesDirectory(for repo: RepositoryConfiguration) -> String? {
        repo.eval?.casesDirectory
    }

    func load() {
        state = .loading
        do {
            repositories = try loadRepositories.run().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            state = .loaded
        } catch {
            state = .error(error)
        }
    }

    func selectRepository(_ repo: RepositoryConfiguration) async {
        selectedRepository = repo
        skills = []
        state = .loadingSkills
        Task { await worktreeModel?.load(repoPath: repo.path.path(percentEncoded: false)) }
        do {
            let loaded = try await loadSkills.run(options: repo)
            guard self.selectedRepository?.id == repo.id else { return }
            self.skills = loaded
            self.state = .loaded
        } catch {
            guard self.selectedRepository?.id == repo.id else { return }
            self.skills = []
            self.state = .error(error)
        }
    }

    func addRepository(
        _ repo: RepositoryConfiguration,
        casesDirectory: String? = nil,
        completedDirectory: String? = nil,
        proposedDirectory: String? = nil
    ) {
        do {
            _ = try configureNewRepository.run(
                repository: repo,
                casesDirectory: casesDirectory,
                completedDirectory: completedDirectory,
                proposedDirectory: proposedDirectory
            )
            load()
        } catch {
            state = .error(error)
        }
    }

    func updateRepository(_ repo: RepositoryConfiguration) {
        do {
            try updateRepository.run(repo)
            if selectedRepository?.id == repo.id {
                selectedRepository = repo
            }
            load()
        } catch {
            state = .error(error)
        }
    }

    func removeRepository(id: UUID) {
        do {
            try removeRepositoryWithSettings.run(id: id)
            if selectedRepository?.id == id {
                selectedRepository = nil
                skills = []
            }
            load()
        } catch {
            state = .error(error)
        }
    }

    func updateCasesDirectory(for repoID: UUID, casesDirectory: String?) {
        do {
            guard var repo = try repositoryStore.find(byID: repoID) else { return }
            if let casesDirectory {
                repo.eval = EvalRepoSettings(casesDirectory: casesDirectory)
            } else {
                repo.eval = nil
            }
            try updateRepository.run(repo)
            load()
        } catch {
            state = .error(error)
        }
    }

    func planSettings(for repo: RepositoryConfiguration) -> PlanRepoSettings? {
        repo.planner
    }

    func proposedDirectory(for repo: RepositoryConfiguration) -> String? {
        repo.planner?.proposedDirectory
    }

    func completedDirectory(for repo: RepositoryConfiguration) -> String? {
        repo.planner?.completedDirectory
    }

    func prradarSettings(for repo: RepositoryConfiguration) -> PRRadarRepoSettings {
        repo.prradar ?? PRRadarRepoSettings()
    }

    func prradarConfig(for repo: RepositoryConfiguration) -> PRRadarRepoConfig? {
        guard !repo.path.path(percentEncoded: false).isEmpty else { return nil }
        let settings = prradarSettings(for: repo)
        guard let outputDirURL = try? dataPathsService.path(for: .prradarOutput(repo.name)) else { return nil }
        let outputDir = outputDirURL.path(percentEncoded: false)
        return PRRadarRepoConfig.make(
            from: repo,
            settings: settings,
            outputDir: outputDir,
            dataRootURL: dataPathsService.rootPath
        )
    }

    func updatePRRadarSettings(for repoID: UUID, rulePaths: [RulePath], diffSource: DiffSource) {
        do {
            guard var repo = try repositoryStore.find(byID: repoID) else { return }
            repo.prradar = PRRadarRepoSettings(rulePaths: rulePaths, diffSource: diffSource)
            try updateRepository.run(repo)
        } catch {
            state = .error(error)
        }
    }

    func updatePlanDirectories(for repoID: UUID, proposedDirectory: String?, completedDirectory: String?) {
        do {
            guard var repo = try repositoryStore.find(byID: repoID) else { return }
            if proposedDirectory != nil || completedDirectory != nil {
                guard proposedDirectory?.isEmpty != true else {
                    state = .error(PlanDirectoryError.emptyDirectory("proposedDirectory"))
                    return
                }
                guard completedDirectory?.isEmpty != true else {
                    state = .error(PlanDirectoryError.emptyDirectory("completedDirectory"))
                    return
                }
                repo.planner = PlanRepoSettings(
                    proposedDirectory: proposedDirectory,
                    completedDirectory: completedDirectory
                )
            } else {
                repo.planner = nil
            }
            try updateRepository.run(repo)
            load()
        } catch {
            state = .error(error)
        }
    }
}

private enum PlanDirectoryError: Error, LocalizedError {
    case emptyDirectory(String)

    var errorDescription: String? {
        switch self {
        case .emptyDirectory(let field):
            return "\(field) cannot be an empty string; pass nil to use the default"
        }
    }
}
