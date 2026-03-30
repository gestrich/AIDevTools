import Foundation

public struct ProviderResult: Sendable {
    public let provider: Provider
    public let error: ProviderError?
    public let events: [[String: JSONValue]]
    public let metrics: ProviderMetrics?
    public let rawStderrPath: URL?
    public let rawStdoutPath: URL?
    public let rawTracePath: URL?
    public let resultText: String?
    public let structuredOutput: [String: JSONValue]?
    public let toolCallSummary: ToolCallSummary?
    public let toolEvents: [ToolEvent]

    public init(
        provider: Provider,
        structuredOutput: [String: JSONValue]? = nil,
        resultText: String? = nil,
        events: [[String: JSONValue]] = [],
        toolEvents: [ToolEvent] = [],
        metrics: ProviderMetrics? = nil,
        rawStdoutPath: URL? = nil,
        rawStderrPath: URL? = nil,
        rawTracePath: URL? = nil,
        error: ProviderError? = nil,
        toolCallSummary: ToolCallSummary? = nil
    ) {
        self.provider = provider
        self.error = error
        self.events = events
        self.metrics = metrics
        self.rawStderrPath = rawStderrPath
        self.rawStdoutPath = rawStdoutPath
        self.rawTracePath = rawTracePath
        self.resultText = resultText
        self.structuredOutput = structuredOutput
        self.toolCallSummary = toolCallSummary
        self.toolEvents = toolEvents
    }
}
