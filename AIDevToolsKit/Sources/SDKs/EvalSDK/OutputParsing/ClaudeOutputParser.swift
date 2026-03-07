import Foundation
import EvalService
import ClaudeCLISDK

public struct ClaudeOutputParser: Sendable {

    public struct Output: Sendable {
        public let rawEvents: [[String: EvalService.JSONValue]]
        public let toolEvents: [ToolEvent]
        public let resultEvent: ClaudeResultEvent?
        public let toolCallSummary: ToolCallSummary
    }

    public init() {}

    public func buildResult(from stdout: String) -> ProviderResult {
        let output = parse(stdout)

        var result = ProviderResult(
            provider: .claude,
            events: output.rawEvents,
            toolEvents: output.toolEvents,
            toolCallSummary: output.toolCallSummary
        )

        guard let resultEvent = output.resultEvent else {
            result.error = ProviderError(
                message: "no result event found in Claude stream-json output",
                subtype: ProviderErrorSubtype.missingResult
            )
            return result
        }

        if let error = resultEvent.providerError {
            result.error = error
            return result
        }

        result.structuredOutput = resultEvent.structuredOutput
        result.resultText = resultEvent.structuredOutput?[StructuredOutputKey.result]?.stringValue ?? ""
        result.metrics = resultEvent.metrics

        return result
    }

    public func parse(_ stdout: String) -> Output {
        var rawEvents: [[String: EvalService.JSONValue]] = []
        var toolEvents: [ToolEvent] = []
        var resultEvent: ClaudeResultEvent?
        var pendingToolCalls: [String: Int] = [:]
        var summary = ToolCallSummary()
        let decoder = JSONDecoder()

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            if let raw = try? decoder.decode([String: EvalService.JSONValue].self, from: data) {
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
                    summary.attempted += 1
                }
            }

            if let event = try? decoder.decode(ClaudeUserEvent.self, from: data),
               event.type == ClaudeEventType.user {
                applyToolResults(from: event, toolEvents: &toolEvents, pendingCalls: &pendingToolCalls, summary: &summary)
            }

            if let event = try? decoder.decode(ClaudeResultEvent.self, from: data),
               event.type == ClaudeEventType.result {
                resultEvent = event
            }
        }

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
        summary: inout ToolCallSummary
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
                    summary.rejected += 1
                } else {
                    summary.errored += 1
                }
            } else {
                summary.succeeded += 1
            }
        }
    }
}
