import PRRadarConfigService
import PRRadarModelsService

public struct DiscoverPRsUseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(filter: PRFilter? = nil) async -> [PRMetadata] {
        let all = await PRDiscoveryService.discoverPRs(config: config)
        guard let filter else { return all }
        return all.filter { filter.matches($0) }
    }

    public func executeSingle(prNumber: Int) async -> PRMetadata? {
        await PRDiscoveryService.discoverPR(number: prNumber, config: config)
    }
}
