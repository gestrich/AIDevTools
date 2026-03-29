import Foundation

public enum MarkdownPipelineFormat: Sendable {
    /// MarkdownPlanner format: `## - [ ] Phase name`
    case phase
    /// ClaudeChain format: `- [ ] Task description`
    case task
}

public struct MarkdownPipelineSource: PipelineSource {
    public let fileURL: URL
    public let format: MarkdownPipelineFormat
    public let appendCreatePRStep: Bool

    public init(fileURL: URL, format: MarkdownPipelineFormat, appendCreatePRStep: Bool? = nil) {
        self.fileURL = fileURL
        self.format = format
        self.appendCreatePRStep = appendCreatePRStep ?? (format == .task)
    }

    public func load() async throws -> Pipeline {
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        var steps: [any PipelineStep] = []
        var index = 0

        for line in content.components(separatedBy: "\n") {
            if let step = parseStep(from: line, index: index) {
                steps.append(step)
                index += 1
            }
        }

        if appendCreatePRStep {
            let prStep = CreatePRStep(
                id: "create-pr",
                description: "Create Pull Request",
                titleTemplate: "{{branch}}",
                bodyTemplate: ""
            )
            steps.append(prStep)
        }

        let name = fileURL.deletingPathExtension().lastPathComponent
        let metadata = PipelineMetadata(name: name, sourceURL: fileURL)
        return Pipeline(id: fileURL.path, steps: steps, metadata: metadata)
    }

    public func markStepCompleted(_ step: any PipelineStep) async throws {
        guard step is CodeChangeStep else { return }
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        let updated = markCompleted(in: content, stepDescription: step.description)
        try updated.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    public func appendSteps(_ steps: [any PipelineStep]) async throws {
        var content = try String(contentsOf: fileURL, encoding: .utf8)
        let suffix = content.hasSuffix("\n") ? "" : "\n"
        content += suffix
        for step in steps {
            content += markdownLine(for: step) + "\n"
        }
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private func parseStep(from line: String, index: Int) -> CodeChangeStep? {
        switch format {
        case .phase:
            if line.hasPrefix("## - [x] ") {
                let desc = String(line.dropFirst("## - [x] ".count))
                return CodeChangeStep(id: String(index), description: desc, isCompleted: true, prompt: desc)
            } else if line.hasPrefix("## - [ ] ") {
                let desc = String(line.dropFirst("## - [ ] ".count))
                return CodeChangeStep(id: String(index), description: desc, isCompleted: false, prompt: desc)
            }
            return nil
        case .task:
            let pattern = #"^\s*- \[([xX ])\]\s*(.+)$"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let checkboxRange = Range(match.range(at: 1), in: line),
                  let descRange = Range(match.range(at: 2), in: line) else {
                return nil
            }
            let isCompleted = line[checkboxRange].lowercased() == "x"
            let desc = String(line[descRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            return CodeChangeStep(id: String(index), description: desc, isCompleted: isCompleted, prompt: desc)
        }
    }

    private func markCompleted(in content: String, stepDescription: String) -> String {
        switch format {
        case .phase:
            return content.replacingOccurrences(
                of: "## - [ ] " + stepDescription,
                with: "## - [x] " + stepDescription
            )
        case .task:
            let escaped = NSRegularExpression.escapedPattern(for: stepDescription)
            let pattern = #"(\s*)- \[ \] "#.appending(escaped)
            let replacement = "$1- [x] \(stepDescription)"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return content }
            let range = NSRange(location: 0, length: content.utf16.count)
            return regex.stringByReplacingMatches(in: content, range: range, withTemplate: replacement)
        }
    }

    private func markdownLine(for step: any PipelineStep) -> String {
        switch format {
        case .phase:
            return "## - [ ] " + step.description
        case .task:
            return "- [ ] " + step.description
        }
    }
}
