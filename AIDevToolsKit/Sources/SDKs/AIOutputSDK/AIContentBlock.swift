import Foundation

/// Accumulated content block stored in a ChatMessage. Built from stream events.
/// - .textDelta chunks accumulate into a single .text block
/// - All other event types map 1:1 to a block
public enum AIContentBlock: Sendable, Equatable {
    case text(String)
    case thinking(String)
    case toolUse(name: String, detail: String)
    case toolResult(name: String, summary: String, isError: Bool)
    case metrics(duration: TimeInterval?, cost: Double?, turns: Int?)
}
