import AIOutputSDK
import Foundation

public struct CodexOutputParser: Sendable {

    public struct Output: Sendable {
        public let rawEvents: [[String: JSONValue]]
        public let toolEvents: [ToolEvent]
        public let toolCallSummary: ToolCallSummary
    }

    public init() {}

    public func buildResult(from stdout: String, provider: Provider) -> ProviderResult {
        let output = parse(stdout)
        return ProviderResult(
            provider: provider,
            events: output.rawEvents,
            toolEvents: output.toolEvents,
            toolCallSummary: output.toolCallSummary
        )
    }

    public func parse(_ stdout: String) -> Output {
        var rawEvents: [[String: JSONValue]] = []
        var toolEvents: [ToolEvent] = []
        var attempted = 0
        var errored = 0
        var succeeded = 0
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

                attempted += 1
                if let exitCode = item.exitCode {
                    if exitCode == 0 {
                        succeeded += 1
                    } else {
                        errored += 1
                    }
                }
            }
        }

        let summary = ToolCallSummary(attempted: attempted, succeeded: succeeded, errored: errored)
        return Output(rawEvents: rawEvents, toolEvents: toolEvents, toolCallSummary: summary)
    }
}
