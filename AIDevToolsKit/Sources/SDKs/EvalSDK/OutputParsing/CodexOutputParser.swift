import Foundation
import CodexCLISDK
import EvalService

public struct CodexOutputParser: Sendable {

    public struct Output: Sendable {
        public let rawEvents: [[String: JSONValue]]
        public let toolEvents: [ToolEvent]
        public let toolCallSummary: ToolCallSummary
    }

    public init() {}

    public func buildResult(from stdout: String) -> ProviderResult {
        let output = parse(stdout)
        return ProviderResult(
            provider: .codex,
            events: output.rawEvents,
            toolEvents: output.toolEvents,
            toolCallSummary: output.toolCallSummary
        )
    }

    public func parse(_ stdout: String) -> Output {
        var rawEvents: [[String: JSONValue]] = []
        var toolEvents: [ToolEvent] = []
        var summary = ToolCallSummary()
        let decoder = JSONDecoder()

        for line in stdout.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { continue }

            if let raw = try? decoder.decode([String: JSONValue].self, from: data) {
                rawEvents.append(raw)
            }

            if let event = try? decoder.decode(CodexStreamEvent.self, from: data),
               let item = event.item,
               item.type == CodexEventItemType.commandExecution,
               event.type == CodexStreamEventType.itemCompleted {
                toolEvents.append(ToolEvent(
                    name: CodexEventItemType.commandExecution,
                    command: item.command,
                    output: item.aggregatedOutput,
                    exitCode: item.exitCode
                ))

                summary.attempted += 1
                if let exitCode = item.exitCode {
                    if exitCode == 0 {
                        summary.succeeded += 1
                    } else {
                        summary.errored += 1
                    }
                }
            }
        }

        return Output(rawEvents: rawEvents, toolEvents: toolEvents, toolCallSummary: summary)
    }
}
