import ArgumentParser

struct PRRadarCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prradar",
        abstract: "PR Radar — AI-powered pull request review pipeline",
        subcommands: [
            PRRadarAnalyzeCommand.self,
            PRRadarCommentCommand.self,
            PRRadarEffectiveDiffCommand.self,
            PRRadarLogsCommand.self,
            PRRadarOutputCommand.self,
            PRRadarPostCommentCommand.self,
            PRRadarPrepareCommand.self,
            PRRadarRefreshCommand.self,
            PRRadarRefreshPRCommand.self,
            PRRadarReportCommand.self,
            PRRadarRunAllCommand.self,
            PRRadarRunCommand.self,
            PRRadarStatusCommand.self,
            PRRadarSyncCommand.self,
            PRRadarViolationsCommand.self,
        ]
    )
}
