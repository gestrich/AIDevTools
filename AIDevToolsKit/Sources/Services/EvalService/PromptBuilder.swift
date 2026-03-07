import Foundation

public struct PromptBuilder: Sendable {

    public init() {}

    public func buildPrimaryPrompt(for evalCase: EvalCase) throws -> String {
        if let prompt = evalCase.prompt {
            return prompt
        }

        guard let task = evalCase.task else {
            throw PromptBuilderError.missingTaskAndInput
        }

        var invocationHint = ""
        if evalCase.skillHint == "explicit" {
            invocationHint = "Use the skill name exactly as specified in the task.\n"
        } else if evalCase.skillHint == "implicit" {
            invocationHint = "Use the most relevant repository skill for this task.\n"
        }

        switch evalCase.mode {
        case .edit:
            return invocationHint
                + "Task:\n\(task)\n\n"
                + "Make the requested changes directly by editing files in the repository. After making changes, return JSON that matches the provided output schema with a summary of what you changed.\n"
        case .structured:
            if let input = evalCase.input {
                return "You are editing a code snippet.\n"
                    + invocationHint
                    + "Task:\n\(task)\n\n"
                    + "Return only the transformed snippet.\n"
                    + "Keep all unrelated code unchanged.\n"
                    + "Return JSON that matches the provided output schema.\n\n"
                    + "Snippet:\n"
                    + "\(input)\n"
            } else {
                return invocationHint
                    + "Task:\n\(task)\n\n"
                    + "Provide a detailed explanation in your response. Name the specific types, files, and patterns involved, and include the exact code snippets needed.\n"
                    + "Return JSON that matches the provided output schema.\n"
            }
        }
    }

    public func renderTemplate(
        _ template: String,
        case evalCase: EvalCase,
        resultText: String,
        repoRoot: URL
    ) -> String {
        var rendered = template
        if evalCase.mode == .edit {
            rendered = "The code changes from this task are currently applied to the repository at \(repoRoot.path). You can read any files to evaluate the changes in full context.\n\n" + rendered
        }
        rendered = rendered.replacingOccurrences(of: "{{result}}", with: resultText)
        rendered = rendered.replacingOccurrences(of: "{{input}}", with: evalCase.input ?? "")
        rendered = rendered.replacingOccurrences(of: "{{id}}", with: evalCase.id)
        rendered = rendered.replacingOccurrences(of: "{{suite}}", with: evalCase.suite ?? "")
        rendered = rendered.replacingOccurrences(of: "{{repo_root}}", with: repoRoot.path)
        return rendered
    }
}

public enum PromptBuilderError: Error, LocalizedError {
    case missingTaskAndInput

    public var errorDescription: String? {
        switch self {
        case .missingTaskAndInput:
            return "case must include either prompt or both task+input"
        }
    }
}
