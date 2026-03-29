import ArgumentParser

public struct ClaudeChainCLI: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "claude-chain",
        abstract: "ClaudeChain CLI - Automated task management with AI assistance",
        version: "1.0.0",
        subcommands: [
            AutoStartCommand.self,
            AutoStartSummaryCommand.self,
            CreateArtifactCommand.self,
            DiscoverCommand.self,
            DiscoverReadyCommand.self,
            FinalizeCommand.self,
            FormatSlackNotificationCommand.self,
            ParseClaudeResultCommand.self,
            ParseEventCommand.self,
            PostPRCommentCommand.self,
            PrepareCommand.self,
            PrepareSummaryCommand.self,
            RunActionScriptCommand.self,
            RunTaskCommand.self,
            SetupCommand.self,
            StatisticsCommand.self,
            StatusCommand.self,
        ]
    )
    
    public init() {}
}