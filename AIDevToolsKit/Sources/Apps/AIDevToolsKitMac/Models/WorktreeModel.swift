import GitSDK
import Observation
import WorktreeFeature

@Observable @MainActor
final class WorktreeModel {

    enum State {
        case idle
        case loading(prior: [WorktreeStatus]?)
        case loaded([WorktreeStatus])
        case error(Error, prior: [WorktreeStatus]?)
    }

    private(set) var state: State = .idle

    private struct UseCases {
        let add: AddWorktreeUseCase
        let list: ListWorktreesUseCase
        let remove: RemoveWorktreeUseCase

        init(gitClient: GitClient) {
            let listUseCase = ListWorktreesUseCase(gitClient: gitClient)
            add = AddWorktreeUseCase(gitClient: gitClient, listUseCase: listUseCase)
            list = listUseCase
            remove = RemoveWorktreeUseCase(gitClient: gitClient, listUseCase: listUseCase)
        }
    }

    private let useCases: UseCases

    init(gitClient: GitClient) {
        useCases = UseCases(gitClient: gitClient)
    }

    var worktrees: [WorktreeStatus]? {
        switch state {
        case .loaded(let statuses): return statuses
        case .loading(let prior): return prior
        case .error(_, let prior): return prior
        case .idle: return nil
        }
    }

    func load(repoPath: String) async {
        let prior = worktrees
        state = .loading(prior: prior)
        do {
            let statuses = try await useCases.list.execute(repoPath: repoPath)
            state = .loaded(statuses)
        } catch {
            state = .error(error, prior: prior)
        }
    }

    func addWorktree(repoPath: String, destination: String, branch: String) async {
        let prior = worktrees
        state = .loading(prior: prior)
        do {
            let statuses = try await useCases.add.execute(repoPath: repoPath, destination: destination, branch: branch)
            state = .loaded(statuses)
        } catch {
            state = .error(error, prior: prior)
        }
    }

    func removeWorktree(repoPath: String, worktreePath: String) async {
        let prior = worktrees
        state = .loading(prior: prior)
        do {
            let statuses = try await useCases.remove.execute(repoPath: repoPath, worktreePath: worktreePath, force: true)
            state = .loaded(statuses)
        } catch {
            state = .error(error, prior: prior)
        }
    }
}
