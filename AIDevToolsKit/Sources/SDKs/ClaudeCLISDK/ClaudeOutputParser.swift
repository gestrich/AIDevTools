import AIOutputSDK
import Foundation

public struct ClaudeOutputParser: Sendable {

    public struct Output: Sendable {
        public let rawEvents: [[String: JSONValue]]
        public let toolEvents: [ToolEvent]
        public let resultEvent: ClaudeResultEvent?
        public let toolCallSummary: ToolCallSummary
    }

    public init() {}

    public func buildResult(from stdout: String, provider: Provider) -> ProviderResult {
        let output = parse(stdout)

        guard let resultEvent = output.resultEvent else {
            return ProviderResult(
                provider: provider,
                events: output.rawEvents,
                toolEvents: output.toolEvents,
                error: ProviderError(
                    message: "no result event found in Claude stream-json output",
                    subtype: ProviderErrorSubtype.missingResult
                ),
                toolCallSummary: output.toolCallSummary
            )
        }

        if let error = resultEvent.providerError {
            return ProviderResult(
                provider: provider,
                events: output.rawEvents,
                toolEvents: output.toolEvents,
                error: error,
                toolCallSummary: output.toolCallSummary
            )
        }

        return ProviderResult(
            provider: provider,
            structuredOutput: resultEvent.structuredOutput,
            resultText: resultEvent.structuredOutput?[StructuredOutputKey.result]?.stringValue ?? "",
            events: output.rawEvents,
            toolEvents: output.toolEvents,
            metrics: resultEvent.metrics,
            toolCallSummary: output.toolCallSummary
        )
    }

    public func parse(_ stdout: String) -> Output {
        var rawEvents: [[String: JSONValue]] = []
        var toolEvents: [ToolEvent] = []
        var resultEvent: ClaudeResultEvent?
        var pendingToolCalls: [String: Int] = [:]
        var attempted = 0
        var rejected = 0
        var errored = 0
        var succeeded = 0
        let decoder = JSONDecoder()

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            if let raw = try? decoder.decode([String: JSONValue].self, from: data) {
                rawEvents.append(raw)
            }

            if let event = try? decoder.decode(ClaudeAssistantEvent.self, from: data),
               event.type == ClaudeEventType.assistant {
                let extracted = extractToolEvents(from: event)
                for toolEvent in extracted {
                    toolEvents.append(toolEvent.event)
                    if let id = toolEvent.toolUseId {
                        pendingToolCalls[id] = toolEvents.count - 1
                    }
                    attempted += 1
                }
            }

            if let event = try? decoder.decode(ClaudeUserEvent.self, from: data),
               event.type == ClaudeEventType.user {
                applyToolResults(
                    from: event,
                    toolEvents: &toolEvents,
                    pendingCalls: &pendingToolCalls,
                    rejected: &rejected,
                    errored: &errored,
                    succeeded: &succeeded
                )
            }

            if let event = try? decoder.decode(ClaudeResultEvent.self, from: data),
               event.type == ClaudeEventType.result {
                resultEvent = event
            }
        }

        let summary = ToolCallSummary(attempted: attempted, succeeded: succeeded, rejected: rejected, errored: errored)
        return Output(rawEvents: rawEvents, toolEvents: toolEvents, resultEvent: resultEvent, toolCallSummary: summary)
    }

    private struct ExtractedToolEvent {
        let event: ToolEvent
        let toolUseId: String?
    }

    private func extractToolEvents(from event: ClaudeAssistantEvent) -> [ExtractedToolEvent] {
        guard let content = event.message?.content else { return [] }
        return content.compactMap { block in
            guard block.type == ClaudeContentBlockType.toolUse,
                  let name = block.name,
                  name != ClaudeToolName.structuredOutput
            else { return nil }

            let inputKeys = block.input.map { Array($0.keys).sorted() } ?? []
            let command = name == ClaudeToolName.bash ? block.input?[ClaudeToolInputKey.command]?.stringValue : nil
            let skillName = name == ClaudeToolName.skill ? block.input?[ClaudeToolInputKey.skill]?.stringValue : nil
            let filePath = name == ClaudeToolName.read ? block.input?[ClaudeToolInputKey.filePath]?.stringValue : nil
            let toolEvent = ToolEvent(name: name, inputKeys: inputKeys, command: command, skillName: skillName, filePath: filePath)
            return ExtractedToolEvent(event: toolEvent, toolUseId: block.id)
        }
    }

    private func applyToolResults(
        from event: ClaudeUserEvent,
        toolEvents: inout [ToolEvent],
        pendingCalls: inout [String: Int],
        rejected: inout Int,
        errored: inout Int,
        succeeded: inout Int
    ) {
        guard let content = event.message?.content else { return }
        for block in content {
            guard block.type == ClaudeContentBlockType2.toolResult,
                  let toolUseId = block.toolUseId else { continue }

            let isError = block.isError ?? false
            let outputText = block.content?.summary

            guard let index = pendingCalls.removeValue(forKey: toolUseId) else { continue }
            toolEvents[index].output = outputText
            if isError {
                let isRejected = outputText?.contains("requires approval") == true
                    || outputText?.contains("not allowed") == true
                if isRejected {
                    rejected += 1
                } else {
                    errored += 1
                }
            } else {
                succeeded += 1
            }
        }
    }
}
