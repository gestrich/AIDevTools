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
                    let (gitHub, _) = try await GitHubServiceFactory.create(repoPath: config.repoPath, githubAccount: config.githubAccount)

                    continuation.yield(.log(text: "Fetching PRs from GitHub...\n"))

                    let limitNum = limit.flatMap(Int.init) ?? 300

                    if let cacheURL = config.gitHubCacheURL {
                        let service = GitHubPRService(rootURL: cacheURL, apiClient: gitHub)

                        _ = try await service.updateAllPRs()
                        try await service.updateRepository()

                        let discoveredPRs = PRDiscoveryService.discoverPRs(gitHubCacheURL: cacheURL)
                        let filteredPRs = discoveredPRs.filter { filter.matches($0) }
                        continuation.yield(.completed(output: FetchPRListResult(prList: filteredPRs, gitHubPRService: service)))
                        continuation.finish()
                    } else {
                        let prs = try await gitHub.listPullRequests(limit: limitNum, filter: filter)

                        let repo = try await gitHub.getRepository()

                        let authorCache = AuthorCacheService()
                        let authorLogins = Set(prs.compactMap { $0.author?.login })
                        let nameMap = authorLogins.isEmpty ? [:] : try await gitHub.resolveAuthorNames(logins: authorLogins, cache: authorCache)

                        let encoder = JSONEncoder()
                        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

                        for pr in prs.map({ $0.withAuthorNames(from: nameMap) }) {
                            let metadataDir = PRRadarPhasePaths.metadataDirectory(
                                outputDir: config.resolvedOutputDir,
                                prNumber: pr.number
                            )
                            try PRRadarPhasePaths.ensureDirectoryExists(at: metadataDir)
                            let prData = try encoder.encode(pr)
                            try prData.write(to: URL(fileURLWithPath: "\(metadataDir)/\(PRRadarPhasePaths.ghPRFilename)"))

                            let repoData = try encoder.encode(repo)
                            try repoData.write(to: URL(fileURLWithPath: "\(metadataDir)/\(PRRadarPhasePaths.ghRepoFilename)"))
                        }

                        let discoveredPRs = PRDiscoveryService.discoverPRs(
                            outputDir: config.resolvedOutputDir,
                            repoSlug: repoSlug
                        )
                        let filteredPRs = discoveredPRs.filter { filter.matches($0) }
                        continuation.yield(.completed(output: FetchPRListResult(prList: filteredPRs, gitHubPRService: nil)))
                        continuation.finish()
                    }
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }
}
