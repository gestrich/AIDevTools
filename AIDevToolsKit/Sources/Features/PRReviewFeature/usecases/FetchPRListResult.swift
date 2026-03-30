import GitHubService
import PRRadarModelsService

public struct FetchPRListResult: Sendable {
    public let prList: [PRMetadata]
    /// The `GitHubPRService` created during the fetch, when the shared GitHub cache is configured.
    /// Callers that need reactive updates (e.g. Mac app models) can subscribe to `gitHubPRService.changes()`.
    public let gitHubPRService: (any GitHubPRServiceProtocol)?
}
