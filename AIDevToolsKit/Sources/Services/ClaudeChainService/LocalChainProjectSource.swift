import Foundation

public struct LocalChainProjectSource: ChainProjectSource {

    private let repoPath: URL
    private let discoveryService: any ChainDiscoveryService

    public init(repoPath: URL, discoveryService: any ChainDiscoveryService = LocalChainDiscoveryService()) {
        self.repoPath = repoPath
        self.discoveryService = discoveryService
    }

    public func listChains(useCache: Bool) async throws -> ChainListResult {
        let sources = try discoveryService.discoverSources(repoPath: repoPath)
        var projects: [ChainProject] = []
        var failures: [ChainFetchFailure] = []

        await withTaskGroup(of: Result<ChainProject, Error>.self) { group in
            for source in sources {
                group.addTask {
                    do {
                        return .success(try await source.loadProject())
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let project):
                    projects.append(project)
                case .failure(let error):
                    failures.append(ChainFetchFailure(context: "Failed to load chain from disk", underlyingError: error))
                }
            }
        }

        return ChainListResult(projects: projects.sorted { $0.name < $1.name }, failures: failures)
    }
}
