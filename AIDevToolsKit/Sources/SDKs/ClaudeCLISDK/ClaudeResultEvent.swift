import Foundation

public struct ClaudeResultEvent: Codable, Sendable {
    public let type: String
    public let isError: Bool?
    public let subtype: String?
    public let errors: JSONValue?
    public let structuredOutput: JSONValue?
    public let durationMs: Int?
    public let totalCostUsd: Double?
    public let numTurns: Int?
    public let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case type
        case isError = "is_error"
        case subtype
        case errors
        case structuredOutput = "structured_output"
        case durationMs = "duration_ms"
        case totalCostUsd = "total_cost_usd"
        case numTurns = "num_turns"
        case sessionId = "session_id"
    }
}
