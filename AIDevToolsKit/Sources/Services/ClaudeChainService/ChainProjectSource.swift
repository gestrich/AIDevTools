public protocol ChainProjectSource: Sendable {
    func listChains(useCache: Bool) async throws -> ChainListResult
}
