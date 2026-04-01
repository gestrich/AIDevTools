import Foundation
import GitHubService
import Logging
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

private let logger = Logger(label: "FetchPRListUseCase")

public struct FetchPRListUseCase: StreamingUseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(
        filter: PRFilter
    ) -> AsyncThrowingStream<PhaseProgress<FetchPRListResult>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .diff))

            Task {
                do {
                    let cacheURL = try config.requireGitHubCacheURL()
                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

                    continuation.yield(.log(text: "Fetching PRs from GitHub...\n"))

                    let service = GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
                    let fetchedPRs = try await service.updateAllPRs(filter: PRFilter(state: .open))

                    try await service.updateRepository()

                    let filteredPRs = fetchedPRs
                        .compactMap { try? $0.toPRMetadata() }
                        .filter { filter.matches($0) }
                        .sorted { $0.number > $1.number }

                    continuation.yield(.completed(output: FetchPRListResult(prList: filteredPRs, gitHubPRService: service)))
                    continuation.finish()
                } catch {
                    logger.error("execute() error", metadata: ["error": "\(error.localizedDescription)"])
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

}
