import AIOutputSDK
import ClaudeChainFeature
import Foundation
import ProviderRegistryService

@MainActor @Observable
final class ClaudeChainModel {

    enum State {
        case idle
        case loadingChains
        case loaded([ChainProject])
        case executing(projectName: String, status: String)
        case error(Error)
    }

    private(set) var state: State = .idle

    private var activeClient: any AIClient
    private let listChainsUseCase: ListChainsUseCase
    private let providerRegistry: ProviderRegistry

    init(
        listChainsUseCase: ListChainsUseCase = ListChainsUseCase(),
        providerRegistry: ProviderRegistry
    ) {
        self.listChainsUseCase = listChainsUseCase
        self.providerRegistry = providerRegistry

        guard let client = providerRegistry.defaultClient else {
            preconditionFailure("ClaudeChainModel requires at least one configured provider")
        }
        self.activeClient = client
    }

    func loadChains(for repoPath: URL) {
        state = .loadingChains
        Task {
            do {
                let projects = try listChainsUseCase.run(options: .init(repoPath: repoPath))
                state = .loaded(projects)
            } catch {
                state = .error(error)
            }
        }
    }

    func executeChain(projectName: String, repoPath: URL) {
        state = .executing(projectName: projectName, status: "Starting...")
        Task {
            do {
                let useCase = ExecuteChainUseCase(client: activeClient)
                state = .executing(projectName: projectName, status: "Running AI task...")
                let result = try await useCase.run(
                    options: .init(repoPath: repoPath, projectName: projectName)
                ) { progress in
                    // Phase 4 will add full streaming support
                }
                if result.success {
                    let status = result.prURL.map { "PR created: \($0)" } ?? result.message
                    state = .executing(projectName: projectName, status: status)
                    loadChains(for: repoPath)
                } else {
                    state = .error(
                        NSError(
                            domain: "ClaudeChainModel",
                            code: 0,
                            userInfo: [NSLocalizedDescriptionKey: result.message]
                        )
                    )
                }
            } catch {
                state = .error(error)
            }
        }
    }
}
