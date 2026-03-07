import CLISDK

@CLIProgram
public struct Codex {
    @CLICommand
    public struct Exec {
        @Flag public var skipGitRepoCheck: Bool = false
        @Flag public var ephemeral: Bool = false
        @Option("--output-schema") public var outputSchema: String?
        @Option("-o") public var outputFile: String?
        @Flag public var json: Bool = false
        @Flag public var fullAuto: Bool = false
        @Option public var model: String?
        @Positional public var prompt: String
    }
}
