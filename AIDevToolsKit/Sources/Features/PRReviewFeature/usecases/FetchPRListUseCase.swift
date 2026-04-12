import CredentialService
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
                    guard let account = config.githubAccount, !account.isEmpty else {
                        throw CredentialError.notConfigured(account: config.name)
                    }
                    let gitHub = try await GitHubServiceFactory.createGitHubAPI(repoPath: config.repoPath, githubAccount: account, explicitToken: config.explicitToken)

                    continuation.yield(.log(text: "Fetching PRs from GitHub...\n"))

                    let startTime = Date()
                    logger.trace("execute: start", metadata: ["repo": "\(config.name)"])

                    let service = GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
                    let fetchedPRs = try await service.updatePRs(filter: filter)

                    let elapsed = Date().timeIntervalSince(startTime)
                    logger.trace(
                        "execute: completed",
                        metadata: [
                            "repo": "\(config.name)",
                            "fetched": "\(fetchedPRs.count)",
                            "elapsed": "\(String(format: "%.2f", elapsed))s",
                        ]
                    )

                    try await service.updateRepository()

                    // Swallowing intentionally: a PR that fails to parse is omitted from
                    // the list rather than aborting the entire fetch.
                    let filteredPRs = fetchedPRs
                        .compactMap { try? $0.toPRMetadata() }
                        .filter { filter.matches($0) }
                        .sorted { $0.number > $1.number }

                    continuation.yield(.completed(output: FetchPRListResult(prList: filteredPRs, gitHubPRService: service)))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

}
