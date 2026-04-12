import AIOutputSDK
import PRRadarModelsService

public enum TaskProgress: Sendable {
    case prompt(text: String)
    case streamEvent(AIStreamEvent)
    case completed(result: RuleOutcome)
}
