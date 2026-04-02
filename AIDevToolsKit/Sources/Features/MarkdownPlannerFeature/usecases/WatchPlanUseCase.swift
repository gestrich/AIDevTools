import AIOutputSDK
import Foundation
import MarkdownPlannerService
import UseCaseSDK

public struct WatchPlanUseCase: StreamingUseCase {

    public init() {}

    public func stream(url: URL) -> AsyncStream<(String, [PlanPhase])> {
        AsyncStream { continuation in
            let task = Task {
                for await content in FileWatcher(url: url).contentStream() {
                    let phases = PlanPhase.parsePhases(from: content)
                    continuation.yield((content, phases))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
