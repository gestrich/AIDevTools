import EvalService
import Foundation
import PlanRunnerService
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

    var repositories: [RepositoryInfo] = []
    var selectedRepository: RepositoryInfo?
    var skills: [Skill] = []
    var isLoadingSkills: Bool = false
    var state: State = .idle

    private let repoStore: RepositoryStore
    private let evalSettingsStore: EvalRepoSettingsStore
    private let planSettingsStore: PlanRepoSettingsStore
    private let loadRepositories: LoadRepositoriesUseCase
    private let loadSkills: LoadSkillsUseCase
    private let addRepository: AddRepositoryUseCase
    private let removeRepository: RemoveRepositoryUseCase
    private let updateRepository: UpdateRepositoryUseCase

    init(
        repoStore: RepositoryStore,
        evalSettingsStore: EvalRepoSettingsStore,
        planSettingsStore: PlanRepoSettingsStore,
        loadRepositories: LoadRepositoriesUseCase,
        loadSkills: LoadSkillsUseCase,
        addRepository: AddRepositoryUseCase,
        removeRepository: RemoveRepositoryUseCase,
        updateRepository: UpdateRepositoryUseCase
    ) {
        self.repoStore = repoStore
        self.evalSettingsStore = evalSettingsStore
        self.planSettingsStore = planSettingsStore
        self.loadRepositories = loadRepositories
        self.loadSkills = loadSkills
        self.addRepository = addRepository
        self.removeRepository = removeRepository
        self.updateRepository = updateRepository
    }

    func evalConfig(for repo: RepositoryInfo) -> RepositoryEvalConfig? {
        guard let settings = try? evalSettingsStore.settings(forRepoId: repo.id) else { return nil }
        return RepositoryEvalConfig(
            casesDirectory: settings.resolvedCasesDirectory(repoPath: repo.path),
            outputDirectory: repoStore.outputDirectory(for: repo),
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
        path: URL,
        name: String? = nil,
        casesDirectory: String? = nil,
        completedDirectory: String? = nil,
        proposedDirectory: String? = nil
    ) {
        do {
            let repo = try addRepository.run(path: path, name: name)
            if let casesDirectory {
                try evalSettingsStore.update(repoId: repo.id, casesDirectory: casesDirectory)
            }
            if completedDirectory != nil || proposedDirectory != nil {
                try planSettingsStore.update(
                    repoId: repo.id,
                    proposedDirectory: proposedDirectory,
                    completedDirectory: completedDirectory
                )
            }
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
            try removeRepository.run(id: id)
            try evalSettingsStore.remove(repoId: id)
            try planSettingsStore.remove(repoId: id)
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

    func planSettings(for repo: RepositoryInfo) -> PlanRepoSettings? {
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
