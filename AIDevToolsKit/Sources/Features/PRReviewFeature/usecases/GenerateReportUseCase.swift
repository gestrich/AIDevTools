import Foundation
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct ReportPhaseOutput: Sendable {
    public let report: ReviewReport
    public let markdownContent: String

    public init(report: ReviewReport, markdownContent: String) {
        self.report = report
        self.markdownContent = markdownContent
    }
}

public struct GenerateReportUseCase: StreamingUseCase {

    private let config: PRRadarRepoConfig

    public init(config: PRRadarRepoConfig) {
        self.config = config
    }

    public func execute(prNumber: Int, minScore: String? = nil, commitHash: String? = nil) -> AsyncThrowingStream<PhaseProgress<ReportPhaseOutput>, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.running(phase: .report))

            Task {
                do {
                    let resolvedCommit: String?
                    if let hash = commitHash {
                        resolvedCommit = hash
                    } else {
                        resolvedCommit = await SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
                    }
                    let scoreThreshold = Int(minScore ?? "5") ?? 5

                    continuation.yield(.log(text: "Generating report (min score: \(scoreThreshold))...\n"))

                    let evalsDir = PRRadarPhasePaths.phaseDirectory(
                        outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .analyze, commitHash: resolvedCommit
                    )
                    let tasksDir = PRRadarPhasePaths.phaseSubdirectory(
                        outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .prepare,
                        subdirectory: PRRadarPhasePaths.prepareTasksSubdir, commitHash: resolvedCommit
                    )
                    let focusAreasDir = PRRadarPhasePaths.phaseSubdirectory(
                        outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .prepare,
                        subdirectory: PRRadarPhasePaths.prepareFocusAreasSubdir, commitHash: resolvedCommit
                    )

                    let baseRefName = await PRDiscoveryService.loadGitHubPR(config: config, prNumber: prNumber)?.baseRefName

                    let reportService = ReportGeneratorService()
                    let report = try reportService.generateReport(
                        prNumber: prNumber,
                        baseRefName: baseRefName,
                        minScore: scoreThreshold,
                        evalsDir: evalsDir,
                        tasksDir: tasksDir,
                        focusAreasDir: focusAreasDir
                    )

                    let reportDir = PRRadarPhasePaths.phaseDirectory(
                        outputDir: config.resolvedOutputDir, prNumber: prNumber, phase: .report, commitHash: resolvedCommit
                    )
                    let (_, _) = try reportService.saveReport(report: report, reportDir: reportDir)

                    // Write phase_result.json
                    try PhaseResultWriter.writeSuccess(
                        phase: .report,
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        commitHash: resolvedCommit,
                        stats: PhaseStats(
                            artifactsProduced: report.violations.count
                        )
                    )

                    let markdown = report.toMarkdown()
                    continuation.yield(.log(text: "Report generated: \(report.violations.count) violations\n"))

                    let output = ReportPhaseOutput(report: report, markdownContent: markdown)
                    continuation.yield(.completed(output: output))
                    continuation.finish()
                } catch {
                    continuation.yield(.failed(error: error.localizedDescription, logs: ""))
                    continuation.finish()
                }
            }
        }
    }

    public static func parseOutput(config: PRRadarRepoConfig, prNumber: Int, commitHash: String? = nil) async throws -> ReportPhaseOutput {
        let resolvedCommit: String?
        if let hash = commitHash {
            resolvedCommit = hash
        } else {
            resolvedCommit = await SyncPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
        }

        let report: ReviewReport = try PhaseOutputParser.parsePhaseOutput(
            config: config, prNumber: prNumber, phase: .report, filename: PRRadarPhasePaths.summaryJSONFilename, commitHash: resolvedCommit
        )

        let markdown = try PhaseOutputParser.readPhaseTextFile(
            config: config, prNumber: prNumber, phase: .report, filename: PRRadarPhasePaths.summaryMarkdownFilename, commitHash: resolvedCommit
        )

        return ReportPhaseOutput(report: report, markdownContent: markdown)
    }
}
