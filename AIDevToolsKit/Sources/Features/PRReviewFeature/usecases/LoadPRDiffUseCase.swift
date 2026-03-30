import PRRadarCLIService
import PRRadarConfigService
import PRRadarModels
import UseCaseSDK

public struct LoadPRDiffUseCase: UseCase {

    private let config: RepositoryConfiguration

    public init(config: RepositoryConfiguration) {
        self.config = config
    }

    public func execute(prNumber: Int, commitHash: String? = nil) -> PRDiff? {
        let resolvedCommit = commitHash ?? SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
        return PhaseOutputParser.loadPRDiff(config: config, prNumber: prNumber, commitHash: resolvedCommit)
    }
}
