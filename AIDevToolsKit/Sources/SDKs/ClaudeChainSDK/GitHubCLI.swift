import CLISDK

@CLIProgram("gh")
public struct GitHubCLI {

    @CLICommand("api")
    public struct API {
        @Positional public var endpoint: String
        @Option("--method") public var method: String = "GET"
    }

    @CLICommand("pr")
    public struct PR {
        @CLICommand("list")
        public struct List {
            @Option("--repo") public var repo: String?
            @Option("--state") public var state: String = "all"
            @Option("--limit") public var limit: String = "100"
            @Option("--label") public var label: String?
            @Option("--assignee") public var assignee: String?
            @Option("--json") public var json: String?
        }

        @CLICommand("view")
        public struct View {
            @Positional public var prNumber: String
            @Option("--repo") public var repo: String?
            @Option("--json") public var json: String?
        }

        @CLICommand("comment")
        public struct Comment {
            @Positional public var prNumber: String
            @Option("--repo") public var repo: String?
            @Option("--body") public var body: String
        }

        @CLICommand("close")
        public struct Close {
            @Positional public var prNumber: String
            @Option("--repo") public var repo: String?
        }

        @CLICommand("merge")
        public struct Merge {
            @Positional public var prNumber: String
            @Option("--repo") public var repo: String?
            @Flag("--merge") public var merge: Bool = false
            @Flag("--squash") public var squash: Bool = false
            @Flag("--rebase") public var rebase: Bool = false
        }

        @CLICommand("edit")
        public struct Edit {
            @Positional public var prNumber: String
            @Option("--repo") public var repo: String?
            @Option("--add-label") public var addLabel: String?
        }
    }

    @CLICommand("run")
    public struct Run {
        @CLICommand("list")
        public struct List {
            @Option("--repo") public var repo: String?
            @Option("--workflow") public var workflow: String?
            @Option("--branch") public var branch: String?
            @Option("--limit") public var limit: String = "10"
            @Option("--json") public var json: String?
        }

        @CLICommand("view")
        public struct View {
            @Positional public var runId: String
            @Option("--repo") public var repo: String?
            @Flag("--log") public var log: Bool = false
        }
    }

    @CLICommand("workflow")
    public struct Workflow {
        @CLICommand("run")
        public struct Run {
            @Positional public var workflow: String
            @Option("--repo") public var repo: String?
            @Option("--ref") public var ref: String?
            @Option("--field") public var fields: [String] = []
        }
    }

    @CLICommand("label")
    public struct Label {
        @CLICommand("create")
        public struct Create {
            @Positional public var name: String
            @Option("--description") public var description: String?
            @Option("--color") public var color: String?
        }
    }
}