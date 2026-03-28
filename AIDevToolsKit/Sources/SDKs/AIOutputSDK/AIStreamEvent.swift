import Foundation

/// Emitted by providers during streaming. Text arrives as deltas (small chunks);
/// everything else arrives as discrete complete events.
public enum AIStreamEvent: Sendable {
    case textDelta(String)
    case thinking(String)
    case toolUse(name: String, detail: String)
    case toolResult(name: String, summary: String, isError: Bool)
    case metrics(duration: TimeInterval?, cost: Double?, turns: Int?)
}
