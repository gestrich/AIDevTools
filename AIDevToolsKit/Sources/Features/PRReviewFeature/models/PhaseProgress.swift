import AIOutputSDK
import PRRadarConfigService
import PRRadarModelsService

public enum PhaseProgress<Output: Sendable>: Sendable {
    case running(phase: PRRadarPhase)
    case log(text: String)
    case prepareStreamEvent(AIStreamEvent)
    case taskEvent(task: RuleRequest, event: TaskProgress)
    case progress(current: Int, total: Int)
    case completed(output: Output)
    case failed(error: String, logs: String)
}
