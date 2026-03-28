import ArgumentParser

public struct ClaudeChainCLI: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "claude-chain",
        abstract: "ClaudeChain CLI - Automated task management with AI assistance",
        version: "1.0.0",
        subcommands: [
            PrepareCommand.self,
            FinalizeCommand.self,
            AutoStartCommand.self,
            AutoStartSummaryCommand.self,
            StatisticsCommand.self,
            DiscoverCommand.self,
            DiscoverReadyCommand.self,
            ParseEventCommand.self,
            PostPRCommentCommand.self,
            ParseClaudeResultCommand.self,
            PrepareSummaryCommand.self,
            CreateArtifactCommand.self,
            RunActionScriptCommand.self,
            FormatSlackNotificationCommand.self,
            SetupCommand.self
        ]
    )
    
    public init() {}
}