import Foundation
import EvalService

public struct ClaudeResultEvent: Codable, Sendable {
    let type: String
    public let isError: Bool?
    public let subtype: String?
    public let errors: JSONValue?
    public let structuredOutput: [String: JSONValue]?
    public let durationMs: Int?
    public let totalCostUsd: Double?
    public let numTurns: Int?

    enum CodingKeys: String, CodingKey {
        case type
        case isError = "is_error"
        case subtype
        case errors
        case structuredOutput = "structured_output"
        case durationMs = "duration_ms"
        case totalCostUsd = "total_cost_usd"
        case numTurns = "num_turns"
    }

    public var metrics: ProviderMetrics {
        ProviderMetrics(durationMs: durationMs, costUsd: totalCostUsd, turns: numTurns)
    }

    public var providerError: ProviderError? {
        guard isError == true else { return nil }
        let message = errors.map { "\($0)" } ?? subtype ?? "unknown error"
        return ProviderError(
            message: message,
            subtype: subtype,
            details: errors.map { ["errors": $0] }
        )
    }
}
