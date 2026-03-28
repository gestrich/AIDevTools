import CLISDK

@CLIProgram
public struct Codex {
    @CLICommand
    public struct Exec {
        @Flag public var ephemeral: Bool = false
        @Flag public var fullAuto: Bool = false
        @Flag public var json: Bool = false
        @Option public var model: String?
        @Option("-o") public var outputFile: String?
        @Option("--output-schema") public var outputSchema: String?
        @Flag public var skipGitRepoCheck: Bool = false
        @Positional public var prompt: String

        @CLICommand
        public struct Resume {
            @Flag public var all: Bool = false
            @Flag public var fullAuto: Bool = false
            @Flag public var last: Bool = false
            @Option public var model: String?
            @Positional public var sessionId: String?
            @Positional public var prompt: String?
        }
    }
}
