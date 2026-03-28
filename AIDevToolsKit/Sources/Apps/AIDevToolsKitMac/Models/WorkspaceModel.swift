import EvalService
import Foundation
import MarkdownPlannerService
import RepositorySDK
import SkillBrowserFeature
import SkillService

@MainActor @Observable
final class WorkspaceModel {

    enum State {
        case idle
        case loading
        case loaded
        case error(Error)
    }

    private(set) var repositories: [RepositoryInfo] = []
    private(set) var selectedRepository: RepositoryInfo?
    private(set) var skills: [Skill] = []
    private(set) var isLoadingSkills: Bool = false
    var state: State = .idle

    private let dataPath: URL
    private let evalSettingsStore: EvalRepoSettingsStore
    private let planSettingsStore: MarkdownPlannerRepoSettingsStore
    private let loadRepositories: LoadRepositoriesUseCase
    private let loadSkills: LoadSkillsUseCase
    private let configureNewRepository: ConfigureNewRepositoryUseCase
    private let removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase
    private let updateRepository: UpdateRepositoryUseCase

    init(
        dataPath: URL,
        evalSettingsStore: EvalRepoSettingsStore,
        planSettingsStore: MarkdownPlannerRepoSettingsStore,
        loadRepositories: LoadRepositoriesUseCase,
        loadSkills: LoadSkillsUseCase,
        configureNewRepository: ConfigureNewRepositoryUseCase,
        removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase,
        updateRepository: UpdateRepositoryUseCase
    ) {
        self.dataPath = dataPath
        self.evalSettingsStore = evalSettingsStore
        self.planSettingsStore = planSettingsStore
        self.loadRepositories = loadRepositories
        self.loadSkills = loadSkills
        self.configureNewRepository = configureNewRepository
        self.removeRepositoryWithSettings = removeRepositoryWithSettings
        self.updateRepository = updateRepository
    }

    func evalConfig(for repo: RepositoryInfo) -> RepositoryEvalConfig? {
        guard let settings = try? evalSettingsStore.settings(forRepoId: repo.id) else { return nil }
        return RepositoryEvalConfig(
            casesDirectory: settings.resolvedCasesDirectory(repoPath: repo.path),
            outputDirectory: dataPath.appendingPathComponent(repo.name),
            repoRoot: repo.path
        )
    }

    func casesDirectory(for repo: RepositoryInfo) -> String? {
        try? evalSettingsStore.settings(forRepoId: repo.id)?.casesDirectory
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

    func selectRepository(_ repo: RepositoryInfo) async {
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
        _ repo: RepositoryInfo,
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

    func updateRepository(_ repo: RepositoryInfo) {
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

    func planSettings(for repo: RepositoryInfo) -> MarkdownPlannerRepoSettings? {
        try? planSettingsStore.settings(forRepoId: repo.id)
    }

    func proposedDirectory(for repo: RepositoryInfo) -> String? {
        try? planSettingsStore.settings(forRepoId: repo.id)?.proposedDirectory
    }

    func completedDirectory(for repo: RepositoryInfo) -> String? {
        try? planSettingsStore.settings(forRepoId: repo.id)?.completedDirectory
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
