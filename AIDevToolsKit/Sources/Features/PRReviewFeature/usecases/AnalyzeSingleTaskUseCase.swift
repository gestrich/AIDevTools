import AIOutputSDK
import CredentialService
import Foundation
import GitHubService
import PRRadarCLIService
import PRRadarConfigService
import PRRadarModelsService
import UseCaseSDK

public struct AnalyzeSingleTaskUseCase: StreamingUseCase {

    private let config: PRRadarRepoConfig
    private let aiClient: any AIClient

    public init(config: PRRadarRepoConfig, aiClient: any AIClient) {
        self.config = config
        self.aiClient = aiClient
    }

    /// Execute a single analysis task.
    ///
    /// Routes to `RegexAnalysisService`, `ScriptAnalysisService`, or `AnalysisService`
    /// based on the task's rule analysis type. Callers that already have a `PRDiff`
    /// loaded can pass it to avoid a redundant disk read.
    public func execute(
        task: RuleRequest,
        prNumber: Int,
        commitHash: String? = nil,
        prDiff: PRDiff? = nil
    ) -> AsyncThrowingStream<TaskProgress, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let resolvedCommit: String?
                    if let hash = commitHash {
                        resolvedCommit = hash
                    } else {
                        resolvedCommit = await FetchPRUseCase.resolveCommitHash(config: config, prNumber: prNumber)
                    }

                    let evalsDir = PRRadarPhasePaths.phaseDirectory(
                        outputDir: config.resolvedOutputDir,
                        prNumber: prNumber,
                        phase: .analyze,
                        commitHash: resolvedCommit
                    )

                    try PRRadarPhasePaths.ensureDirectoryExists(at: evalsDir)

                    let result: RuleOutcome

                    if let pattern = task.rule.violationRegex {
                        let resolvedDiff = prDiff ?? PhaseOutputParser.loadPRDiff(
                            config: config, prNumber: prNumber, commitHash: resolvedCommit
                        )
                        let hunks = resolvedDiff?.hunks ?? []
                        let focusedHunks = PRHunk.filterForFocusArea(hunks, focusArea: task.focusArea)
                        let (outcome, output) = RegexAnalysisService().analyzeTask(task, pattern: pattern, hunks: focusedHunks)
                        result = outcome
                        try EvaluationOutputWriter.write(output, to: evalsDir)
                    } else if let scriptPath = task.rule.violationScript {
                        let resolvedDiff = prDiff ?? PhaseOutputParser.loadPRDiff(
                            config: config, prNumber: prNumber, commitHash: resolvedCommit
                        )
                        let hunks = resolvedDiff?.hunks ?? []
                        let focusedHunks = PRHunk.filterForFocusArea(hunks, focusArea: task.focusArea)
                        let (outcome, output) = ScriptAnalysisService().analyzeTask(task, scriptPath: scriptPath, repoPath: config.repoPath, hunks: focusedHunks)
                        result = outcome
                        try EvaluationOutputWriter.write(output, to: evalsDir)
                    } else {
                        let analysisService = AnalysisService(aiClient: aiClient)

                        result = try await analysisService.analyzeTask(
                            task,
                            repoPath: config.repoPath,
                            transcriptDir: evalsDir,
                            onPrompt: { text, _ in
                                continuation.yield(.prompt(text: text))
                            },
                            onStreamEvent: { event in
                                switch event {
                                case .textDelta(let text):
                                    continuation.yield(.output(text: text))
                                case .toolUse(let name, _):
                                    continuation.yield(.toolUse(name: name))
                                default:
                                    break
                                }
                            }
                        )
                    }

                    // Write result to disk
                    let encoder = JSONEncoder()
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    let data = try encoder.encode(result)
                    let resultPath = "\(evalsDir)/\(PRRadarPhasePaths.dataFilePrefix)\(task.taskId).json"
                    try data.write(to: URL(fileURLWithPath: resultPath))

                    // Write task snapshot for cache
                    try AnalysisCacheService.writeTaskSnapshots(tasks: [task], evalsDir: evalsDir)

                    continuation.yield(.completed(result: result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

}
