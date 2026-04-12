import CredentialService
import Foundation
import Logging
import PRRadarModelsService

private let logger = Logger(label: "GitHubPRLoaderUseCase")

public struct GitHubPRLoaderUseCase {

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

    private let config: GitHubRepoConfig

    public init(config: GitHubRepoConfig) {
        self.config = config
    }

    public func execute(filter: PRFilter) -> AsyncStream<Event> {
        AsyncStream { continuation in
            Task {
                continuation.yield(.listLoadStarted)

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

                let cachedGHPRs = await service.readAllCachedPRs()
                let cachedPRs: [PRMetadata] = cachedGHPRs
                    .compactMap { try? $0.toPRMetadata() }
                    .sorted { $0.number > $1.number }
                let filteredCached = cachedPRs.filter { filter.matches($0) }
                continuation.yield(.cached(filteredCached))

                let cachedByNumber: [Int: PRMetadata] = Dictionary(
                    uniqueKeysWithValues: cachedPRs.map { ($0.number, $0) }
                )

                continuation.yield(.listFetchStarted)

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

                var rateLimited = false
                for pr in fetchedPRs {
                    if rateLimited { break }

                    // If the PR hasn't changed since the last disk-cached version, read enrichment
                    // from disk cache rather than hitting GitHub again. On first load (cache miss)
                    // the service falls through to a live fetch automatically.
                    let isUnchanged = cachedByNumber[pr.number].map { $0.updatedAt == pr.updatedAt } ?? false

                    continuation.yield(.prFetchStarted(prNumber: pr.number))
                    do {
                        let enriched = try await enrichPR(pr, using: service, useCache: isUnchanged)
                        continuation.yield(.prUpdated(enriched))
                    } catch {
                        let msg = error.localizedDescription
                        logger.error("execute(filter:): enrichment failed for PR #\(pr.number): \(error)")
                        if msg.lowercased().contains("rate limit") || msg.lowercased().contains("access forbidden") {
                            rateLimited = true
                        }
                        continuation.yield(.prFetchFailed(prNumber: pr.number, error: msg))
                    }
                }
                if rateLimited {
                    continuation.yield(.listFetchFailed("GitHub rate limit hit — enrichment stopped. Wait a minute then refresh."))
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
                    let enriched = try await enrichPR(base, using: service, useCache: false)
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
        let gitHub = try await GitHubServiceFactory.createGitHubAPI(
            repoPath: config.repoPath,
            githubAccount: config.account,
            explicitToken: config.token
        )
        return GitHubPRService(rootURL: config.cacheURL, apiClient: gitHub)
    }

    private func enrichPR(
        _ pr: PRMetadata,
        using service: GitHubPRService,
        useCache: Bool
    ) async throws -> PRMetadata {
        // service.comments() already fetches reviews internally (getPullRequestComments calls
        // listReviews). Calling service.reviews() separately would duplicate that request.
        let comments = try await service.comments(number: pr.number, useCache: useCache)
        let checkRuns = try await service.checkRuns(number: pr.number, useCache: useCache)
        // isMergeable has no disk cache — skip the live call when reading from cache to avoid
        // an extra API call for PRs whose updatedAt hasn't changed.
        let isMergeable: Bool? = useCache ? nil : (try await service.isMergeable(number: pr.number))

        var enriched = pr
        enriched.githubComments = comments
        enriched.reviews = comments.reviews
        enriched.checkRuns = checkRuns
        enriched.isMergeable = isMergeable

        return enriched
    }
}
