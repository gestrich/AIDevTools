import AIOutputSDK

/// Composes a stable system prompt for contextual chat from multiple sources.
struct SystemPromptBuilder {
    @MainActor
    func build(for context: any ViewChatContext) -> String {
        var parts: [String] = []

        parts.append(baseInstructions)

        let descriptors = context.responseRouter.responseDescriptors
        if !descriptors.isEmpty {
            parts.append(structuredOutputInstructions(for: descriptors))
        }

        parts.append(cliInstructions(workingDirectory: context.chatWorkingDirectory))
        parts.append(deepLinkInstructions())
        parts.append(context.chatSystemPrompt)

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Private

    private var baseInstructions: String {
        """
        You are an AI assistant embedded in AIDevTools, a Mac app for AI-assisted software development. \
        You have context about the current view and can interact with the app through structured outputs and CLI commands.
        """
    }

    private func structuredOutputInstructions(for descriptors: [AIResponseDescriptor]) -> String {
        var lines: [String] = [
            "You can send structured data to the app by embedding XML tags in your response:",
            "",
            "<app-response name=\"responseName\">{\"key\": \"value\"}</app-response>",
            "",
            "Available responses:"
        ]

        let queries = descriptors.filter { $0.kind == .query }
        let actions = descriptors.filter { $0.kind == .action }

        if !queries.isEmpty {
            lines.append("")
            lines.append("Queries — the app replies with data you can use:")
            for d in queries {
                lines.append("  \(d.name): \(d.description)")
                lines.append("  Schema: \(d.jsonSchema)")
            }
        }

        if !actions.isEmpty {
            lines.append("")
            lines.append("Actions — the app executes these:")
            for d in actions {
                lines.append("  \(d.name): \(d.description)")
                lines.append("  Schema: \(d.jsonSchema)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func deepLinkInstructions() -> String {
        let path = DeepLinkWatcher.fileURL.path(percentEncoded: false)
        return """
        After CLI commands that modify data the app is displaying, write a deep link to \(path) to trigger navigation.
        Supported URLs:
        - aidevtools://tab/{tabName} — switch to a tab (architecture, claudeChain, evals, plans, prradar, skills)
        Example: echo "aidevtools://tab/plans" > "\(path)"
        """
    }

    private func cliInstructions(workingDirectory: String) -> String {
        """
        You can run CLI commands to read and modify data.
        Working directory: \(workingDirectory)
        Available CLI tool: ai-dev-tools-kit
        Run `ai-dev-tools-kit help` to see available subcommands.
        """
    }
}
