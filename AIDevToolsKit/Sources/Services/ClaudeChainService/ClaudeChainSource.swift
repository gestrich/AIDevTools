import PipelineSDK

/// Unified protocol for ClaudeChain task sources covering both execution and display.
///
/// Extends `TaskSource` so any implementation is usable by `PipelineRunner`'s
/// `drainTaskSource` loop. GitHub service should be injected at construction
/// time and used by `loadDetail()`.
public protocol ClaudeChainSource: TaskSource {
    func loadProject() async throws -> ChainProject
    func loadDetail() async throws -> ChainProjectDetail
}
