import CLISDK

@CLIProgram("git")
public struct GitCLI {

    @CLICommand
    public struct Init {}

    @CLICommand
    public struct Fetch {
        @Positional public var remote: String
        @Positional public var branch: String
    }

    @CLICommand
    public struct Add {
        @Positional public var files: [String]
    }

    @CLICommand
    public struct Commit {
        @Option("-m") public var message: String
    }

    @CLICommand
    public struct Branch {
        @Positional public var name: String
    }

    @CLICommand
    public struct Worktree {
        @CLICommand
        public struct Add {
            @Positional public var destination: String
            @Positional public var commitish: String
        }

        @CLICommand
        public struct Remove {
            @Flag public var force: Bool = false
            @Positional public var path: String
        }

        @CLICommand
        public struct Prune {}
    }
}
