import Foundation
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct DeletePRDataUseCase: UseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(prNumber: Int) async throws -> PRMetadata {
        let prDir = config.prDataDirectory(for: prNumber)

        if FileManager.default.fileExists(atPath: prDir) {
            try FileManager.default.removeItem(atPath: prDir)
        }

        let syncUseCase = SyncPRUseCase(config: config)
        for try await progress in syncUseCase.execute(prNumber: prNumber) {
            switch progress {
            case .failed(let error, _):
                throw DeletePRDataError.syncFailed(error)
            default:
                break
            }
        }

        if let metadata = await PRDiscoveryService.discoverPR(number: prNumber, config: config) {
            return metadata
        }

        return PRMetadata.fallback(number: prNumber)
    }
}

public enum DeletePRDataError: LocalizedError {
    case syncFailed(String)

    public var errorDescription: String? {
        switch self {
        case .syncFailed(let message):
            "Failed to re-fetch PR data: \(message)"
        }
    }
}
