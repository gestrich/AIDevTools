import CLISDK

public enum ClaudeOutputFormat: String, Sendable {
    case text
    case json
    case streamJSON = "stream-json"
}

@CLIProgram("claude")
public struct Claude {
    @Flag("--continue") public var continueConversation: Bool = false
    @Flag("--dangerously-skip-permissions") public var dangerouslySkipPermissions: Bool = false
    @Option("--json-schema") public var jsonSchema: String?
    @Option public var model: String?
    @Option("--output-format") public var outputFormat: String?
    @Flag("-p") public var printMode: Bool = false
    @Option("--resume") public var resume: String?
    @Flag public var verbose: Bool = false
    @Positional public var prompt: String
}
