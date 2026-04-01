import EvalService
import Foundation
import MarkdownPlannerService
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
        case error(Error)
    }

    private(set) var repositories: [RepositoryConfiguration] = []
    private(set) var selectedRepository: RepositoryConfiguration?
    private(set) var skills: [SkillInfo] = []
    private(set) var isLoadingSkills: Bool = false
    var state: State = .idle

    private let dataPath: URL
    private let evalSettingsStore: EvalRepoSettingsStore
    private let planSettingsStore: MarkdownPlannerRepoSettingsStore
    private let prradarSettingsStore: PRRadarRepoSettingsStore
    private let loadRepositories: LoadRepositoriesUseCase
    private let loadSkills: LoadSkillsUseCase
    private let configureNewRepository: ConfigureNewRepositoryUseCase
    private let removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase
    private let updateRepository: UpdateRepositoryUseCase

    init(
        dataPath: URL,
        evalSettingsStore: EvalRepoSettingsStore,
        planSettingsStore: MarkdownPlannerRepoSettingsStore,
        prradarSettingsStore: PRRadarRepoSettingsStore,
        loadRepositories: LoadRepositoriesUseCase,
        loadSkills: LoadSkillsUseCase,
        configureNewRepository: ConfigureNewRepositoryUseCase,
        removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase,
        updateRepository: UpdateRepositoryUseCase
    ) {
        self.dataPath = dataPath
        self.evalSettingsStore = evalSettingsStore
        self.planSettingsStore = planSettingsStore
        self.prradarSettingsStore = prradarSettingsStore
        self.loadRepositories = loadRepositories
        self.loadSkills = loadSkills
        self.configureNewRepository = configureNewRepository
        self.removeRepositoryWithSettings = removeRepositoryWithSettings
        self.updateRepository = updateRepository
    }

    func evalConfig(for repo: RepositoryConfiguration) -> RepositoryEvalConfig? {
        guard let settings = repo.eval else { return nil }
        return RepositoryEvalConfig(
            casesDirectory: settings.resolvedCasesDirectory(repoPath: repo.path),
            outputDirectory: dataPath.appendingPathComponent(repo.name),
            repoRoot: repo.path
        )
    }

    func casesDirectory(for repo: RepositoryConfiguration) -> String? {
        repo.eval?.casesDirectory
    }

    func load() {
        state = .loading
        do {
            repositories = try loadRepositories.run()
            state = .loaded
        } catch {
            state = .error(error)
        }
    }

    func selectRepository(_ repo: RepositoryConfiguration) async {
        selectedRepository = repo
        skills = []
        isLoadingSkills = true
        do {
            let loaded = try await loadSkills.run(options: repo)
            guard self.selectedRepository?.id == repo.id else { return }
            self.skills = loaded
        } catch {
            guard self.selectedRepository?.id == repo.id else { return }
            self.skills = []
            self.state = .error(error)
        }
        self.isLoadingSkills = false
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
            if let casesDirectory {
                try evalSettingsStore.update(repoId: repoID, casesDirectory: casesDirectory)
            } else {
                try evalSettingsStore.remove(repoId: repoID)
            }
            load()
        } catch {
            state = .error(error)
        }
    }

    func planSettings(for repo: RepositoryConfiguration) -> MarkdownPlannerRepoSettings? {
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
        let outputDir = dataPath
            .appendingPathComponent("prradar/repos/\(repo.name)")
            .path(percentEncoded: false)
        return PRRadarRepoConfig.make(
            from: repo,
            settings: settings,
            outputDir: outputDir,
            agentScriptPath: settings.agentScriptPath,
            dataRootURL: dataPath
        )
    }

    func updatePRRadarSettings(for repoID: UUID, rulePaths: [RulePath], diffSource: DiffSource, agentScriptPath: String) {
        try? prradarSettingsStore.update(
            repoId: repoID,
            rulePaths: rulePaths,
            diffSource: diffSource,
            agentScriptPath: agentScriptPath
        )
    }

    func updatePlanDirectories(for repoID: UUID, proposedDirectory: String?, completedDirectory: String?) {
        do {
            if proposedDirectory != nil || completedDirectory != nil {
                try planSettingsStore.update(
                    repoId: repoID,
                    proposedDirectory: proposedDirectory,
                    completedDirectory: completedDirectory
                )
            } else {
                try planSettingsStore.remove(repoId: repoID)
            }
            load()
        } catch {
            state = .error(error)
        }
    }
}
