import Foundation
import GitHubService
import PRRadarConfigService
import PRRadarModelsService

@Observable
@MainActor
final class PullRequestsModel {

    enum State {
        case uninitialized
        case loading
        case refreshing([PRMetadata])
        case ready([PRMetadata])
        case failed(String, prior: [PRMetadata]?)
    }

    private(set) var state: State = .uninitialized
    private(set) var fetchingPRNumbers: Set<Int> = []

    let config: PRRadarRepoConfig

    init(config: PRRadarRepoConfig) {
        self.config = config
    }

    // MARK: - Load

    func load() async {
        state = .loading
        let gitHubConfig: GitHubRepoConfig
        do {
            gitHubConfig = try config.makeGitHubRepoConfig()
        } catch {
            state = .failed(error.localizedDescription, prior: nil)
            return
        }
        let useCase = GitHubPRLoaderUseCase(config: gitHubConfig)
        for await event in useCase.execute(filter: config.makeFilter()) {
            handle(event)
        }
    }

    // MARK: - Per-PR Refresh

    func refresh(number: Int) async {
        guard let gitHubConfig = try? config.makeGitHubRepoConfig() else { return }
        let useCase = GitHubPRLoaderUseCase(config: gitHubConfig)
        for await event in useCase.execute(prNumber: number) {
            handle(event)
        }
    }

    // MARK: - Derived

    var prs: [PRMetadata]? {
        switch state {
        case .ready(let list): return list
        case .refreshing(let list): return list
        case .failed(_, let prior): return prior
        case .uninitialized, .loading: return nil
        }
    }

    // MARK: - Event Handling

    private func handle(_ event: GitHubPRLoaderUseCase.Event) {
        switch event {
        case .listLoadStarted, .listFetchStarted:
            break

        case .cached(let metadata):
            switch state {
            case .loading:
                state = .refreshing(metadata)
            default:
                break
            }

        case .fetched(let metadata):
            state = .refreshing(metadata)

        case .listFetchFailed(let message):
            state = .failed(message, prior: prs)

        case .prFetchStarted(let prNumber):
            fetchingPRNumbers.insert(prNumber)

        case .prUpdated(let metadata):
            fetchingPRNumbers.remove(metadata.number)
            state = updatingPR(metadata)

        case .prFetchFailed(let prNumber, _):
            fetchingPRNumbers.remove(prNumber)

        case .completed:
            if let list = prs {
                state = .ready(list)
            }
        }
    }

    private func updatingPR(_ updated: PRMetadata) -> State {
        guard let list = prs else { return .ready([updated]) }
        let newList = list.map { $0.number == updated.number ? updated : $0 }
        switch state {
        case .refreshing: return .refreshing(newList)
        default: return .ready(newList)
        }
    }
}
