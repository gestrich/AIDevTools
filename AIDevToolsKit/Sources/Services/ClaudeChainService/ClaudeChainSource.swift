import PipelineSDK

/// Unified protocol for ClaudeChain task sources covering both execution and display.
///
/// Extends `TaskSource` so any implementation is usable by `PipelineRunner`'s
/// `drainTaskSource` loop. GitHub service should be injected at construction
/// time and used by `loadDetail()`.
public protocol ClaudeChainSource: TaskSource {
    /// Short label shown in UI to distinguish source types, e.g. "maintenance". Nil for standard chains.
    var kindBadge: String? { get }
    func loadProject() async throws -> ChainProject
    func loadDetail() async throws -> ChainProjectDetail
}
