import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct LoadPRDiffUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(prNumber: Int, commitHash: String? = nil) async -> PRDiff? {
        let resolvedCommit: String?
        if let hash = commitHash {
            resolvedCommit = hash
        } else {
            resolvedCommit = await SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
        }
        return PhaseOutputParser.loadPRDiff(config: config, prNumber: prNumber, commitHash: resolvedCommit)
    }
}
