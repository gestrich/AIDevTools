import Foundation
import PipelineSDK

@MainActor @Observable
final class PipelineModel {

    struct NodeState: Identifiable {
        let displayName: String
        let id: String
        var isCompleted: Bool = false
        var isCurrent: Bool = false
    }

    var error: Error?
    var isRunning: Bool = false
    var nodes: [NodeState] = []
    var onEvent: (@MainActor (PipelineEvent) -> Void)?

    @ObservationIgnored private var runningTask: Task<Void, any Error>?

    @discardableResult
    func run(blueprint: PipelineBlueprint) async throws -> PipelineContext {
        isRunning = true
        error = nil
        nodes = blueprint.initialNodeManifest.map {
            NodeState(displayName: $0.displayName, id: $0.id)
        }

        let box = PipelineContextBox()
        let task = Task { [box] in
            let runner = PipelineRunner()
            let finalContext = try await runner.run(
                nodes: blueprint.nodes,
                configuration: blueprint.configuration,
                onProgress: { [weak self] event in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.handleEvent(event)
                        self.onEvent?(event)
                    }
                }
            )
            box.context = finalContext
        }
        runningTask = task

        defer {
            isRunning = false
            runningTask = nil
        }

        try await task.value
        return box.context ?? PipelineContext()
    }

    func stop() {
        runningTask?.cancel()
    }

    // MARK: - Private

    private func handleEvent(_ event: PipelineEvent) {
        switch event {
        case .nodeStarted(let id, let displayName):
            if let index = nodes.firstIndex(where: { $0.id == id }) {
                nodes[index].isCurrent = true
            } else {
                nodes.append(NodeState(displayName: displayName, id: id))
            }
        case .nodeCompleted(let id, _):
            if let index = nodes.firstIndex(where: { $0.id == id }) {
                nodes[index].isCompleted = true
                nodes[index].isCurrent = false
            }
        case .completed, .nodeProgress, .pausedForReview:
            break
        }
    }
}

private final class PipelineContextBox: @unchecked Sendable {
    var context: PipelineContext?
}
