import Foundation
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct FetchPRListUseCase: StreamingUseCase {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(
        limit: String? = nil,
        filter: PRFilter,
        repoSlug: String? = nil
    ) -> AsyncThrowingStream<PhaseProgress<FetchPRListResult>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    guard let cacheURL = config.gitHubCacheURL else {
                        throw FetchError.noDataRoot
                    }

                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

                    continuation.yield(.log(text: "Fetching PRs from GitHub...\n"))

                    let service = GitHubPRService(rootURL: cacheURL, apiClient: gitHub)

                    _ = try await service.updateAllPRs()
                    try await service.updateRepository()

                    let discoveredPRs = PRDiscoveryService.discoverPRs(gitHubCacheURL: cacheURL)
                    let filteredPRs = discoveredPRs.filter { filter.matches($0) }
                    continuation.yield(.completed(output: FetchPRListResult(prList: filteredPRs, gitHubPRService: service)))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    private enum FetchError: LocalizedError {
        case noDataRoot

        var errorDescription: String? {
            "GitHub cache URL not configured; ensure dataRootURL is set on RepositoryConfiguration"
        }
    }
}
