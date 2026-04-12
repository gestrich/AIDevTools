import CredentialService
import Foundation
import GitHubService
import Logging
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

private let logger = Logger(label: "GitHubPRLoaderUseCase")

public struct GitHubPRLoaderUseCase: StreamingUseCase {

    public enum Event: Sendable {
        // List-level events
        case listLoadStarted
        case cached([PRMetadata])
        case listFetchStarted
        case fetched([PRMetadata])
        case listFetchFailed(String)

        // Per-PR events
        case prFetchStarted(prNumber: Int)
        case prUpdated(PRMetadata)
        case prFetchFailed(prNumber: Int, error: String)

        // Terminal
        case completed
    }

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(filter: PRFilter) -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.listLoadStarted)

                let cachedPRs = await PRDiscoveryService.discoverPRs(config: config)
                let filteredCached = cachedPRs.filter { filter.matches($0) }.sorted { $0.number > $1.number }
                continuation.yield(.cached(filteredCached))

                let cachedByNumber: [Int: PRMetadata] = Dictionary(
                    uniqueKeysWithValues: cachedPRs.map { ($0.number, $0) }
                )

                continuation.yield(.listFetchStarted)

                let service: GitHubPRService
                do {
                    service = try await makeService()
                } catch {
                    logger.error("execute(filter:): service setup failed: \(error)")
                    continuation.yield(.listFetchFailed(error.localizedDescription))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                let fetchedGHPRs: [GitHubPullRequest]
                do {
                    fetchedGHPRs = try await service.updatePRs(filter: filter)
                } catch {
                    logger.error("execute(filter:): list fetch failed: \(error)")
                    continuation.yield(.listFetchFailed(error.localizedDescription))
                    continuation.yield(.completed)
                    continuation.finish()
                    return
                }

                // Swallowing intentionally: a PR that fails to parse is omitted from the list
                // rather than aborting the entire fetch.
                let fetchedPRs = fetchedGHPRs
                    .compactMap { try? $0.toPRMetadata() }
                    .filter { filter.matches($0) }
                    .sorted { $0.number > $1.number }

                continuation.yield(.fetched(fetchedPRs))

                for pr in fetchedPRs {
                    if let prior = cachedByNumber[pr.number], prior.updatedAt == pr.updatedAt {
                        continue
                    }

                    continuation.yield(.prFetchStarted(prNumber: pr.number))
                    do {
                        let enriched = try await enrichPR(pr, using: service)
                        continuation.yield(.prUpdated(enriched))
                    } catch {
                        logger.error("execute(filter:): enrichment failed for PR #\(pr.number): \(error)")
                        continuation.yield(.prFetchFailed(prNumber: pr.number, error: error.localizedDescription))
                    }
                }

                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    public func execute(prNumber: Int) -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.prFetchStarted(prNumber: prNumber))

                do {
                    let service = try await makeService()
                    let ghPR = try await service.pullRequest(number: prNumber, useCache: false)
                    let base = try ghPR.toPRMetadata()
                    let enriched = try await enrichPR(base, using: service)
                    continuation.yield(.prUpdated(enriched))
                } catch {
                    logger.error("execute(prNumber:): failed for PR #\(prNumber): \(error)")
                    continuation.yield(.prFetchFailed(prNumber: prNumber, error: error.localizedDescription))
                }

                continuation.yield(.completed)
                continuation.finish()
            }
        }
    }

    private func makeService() async throws -> GitHubPRService {
        let cacheURL = try config.requireGitHubCacheURL()
        guard let account = config.githubAccount, !account.isEmpty else {
            throw CredentialError.notConfigured(account: config.name)
        }
        let gitHub = try await GitHubServiceFactory.createGitHubAPI(
            repoPath: config.repoPath,
            githubAccount: account,
            explicitToken: config.explicitToken
        )
        return GitHubPRService(rootURL: cacheURL, apiClient: gitHub)
    }

    private func enrichPR(_ pr: PRMetadata, using service: GitHubPRService) async throws -> PRMetadata {
        let comments = try await service.comments(number: pr.number, useCache: false)
        let reviews = try await service.reviews(number: pr.number, useCache: false)
        let checkRuns = try await service.checkRuns(number: pr.number, useCache: false)
        let isMergeable = try await service.isMergeable(number: pr.number)

        var enriched = pr
        enriched.githubComments = comments
        enriched.reviews = reviews
        enriched.checkRuns = checkRuns
        enriched.isMergeable = isMergeable
        return enriched
    }
}
