import CLISDK

@CLIProgram("git")
public struct GitCLI {

    @CLICommand
    public struct Add {
        @Flag("-A") public var all: Bool = false
        @Positional public var files: [String]
    }

    @CLICommand
    public struct Branch {
        @Positional public var name: String
    }

    @CLICommand
    public struct Checkout {
        @Flag("-b") public var createBranch: Bool = false
        @Positional public var ref: String
    }

    @CLICommand
    public struct Commit {
        @Option("-m") public var message: String
    }

    @CLICommand
    public struct Diff {
        @Flag("--cached") public var cached: Bool = false
        @Flag("--name-only") public var nameOnly: Bool = false
        @Option("--diff-filter") public var diffFilter: String?
        @Positional public var ref1: String?
        @Positional public var ref2: String?
        @Positional public var pattern: String?
    }

    @CLICommand
    public struct Fetch {
        @Option("--depth") public var depth: String?
        @Positional public var remote: String
        @Positional public var branch: String
    }

    @CLICommand
    public struct Init {}

    @CLICommand
    public struct Push {
        @Flag("-u") public var setUpstream: Bool = false
        @Flag("--force") public var force: Bool = false
        @Positional public var remote: String
        @Positional public var branch: String
    }

    @CLICommand
    public struct Remote {
        @CLICommand("get-url")
        public struct GetURL {
            @Positional public var name: String
        }

        @CLICommand("set-url")
        public struct SetURL {
            @Positional public var name: String
            @Positional public var url: String
        }
    }

    @CLICommand
    public struct Status {
        @Flag public var porcelain: Bool = false
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

    @CLICommand
    public struct Config {
        @Positional public var key: String
        @Positional public var value: String
    }

    @CLICommand("cat-file")
    public struct CatFile {
        @Flag("-t") public var type: Bool = false
        @Positional public var object: String
    }

    @CLICommand("rev-list")
    public struct RevList {
        @Flag("--count") public var count: Bool = false
        @Positional public var range: String
    }

    @CLICommand("rev-parse")
    public struct RevParse {
        @Flag("--abbrev-ref") public var abbrevRef: Bool = false
        @Positional public var ref: String
    }
}
