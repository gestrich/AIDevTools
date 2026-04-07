import Foundation
import PipelineFeature
import PipelineSDK

@MainActor @Observable
final class PipelineModel {

    struct NodeState: Identifiable {
        let displayName: String
        let id: String
        var isCompleted: Bool = false
        var isCurrent: Bool = false
    }

    enum ModelState {
        case idle
        case running
    }

    private(set) var state: ModelState = .idle
    private(set) var nodes: [NodeState] = []
    var onEvent: (@MainActor (PipelineEvent) -> Void)?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    @ObservationIgnored private var runningTask: Task<PipelineContext, any Error>?

    @discardableResult
    func run(blueprint: PipelineBlueprint) async throws -> PipelineContext {
        state = .running
        nodes = blueprint.initialNodeManifest.map {
            NodeState(displayName: $0.displayName, id: $0.id)
        }

        let task = Task<PipelineContext, any Error> {
            try await RunBlueprintUseCase().run(blueprint: blueprint) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.handleEvent(event)
                    self.onEvent?(event)
                }
            }
        }
        runningTask = task

        defer {
            state = .idle
            runningTask = nil
        }

        return try await task.value
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
        case .completed, .nodeProgress, .pausedForReview, .taskDiscovered:
            break
        }
    }
}
