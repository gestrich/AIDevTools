import Foundation
import PlanFeature
import PlanService
import Observation

@Observable
@MainActor
final class ActivePlanModel {
    enum ModelState {
        case idle
        case watching(content: String, phases: [PlanPhase])
        case error(Error, prior: (content: String, phases: [PlanPhase])?)
    }

    private(set) var state: ModelState = .idle
    private var watchTask: Task<Void, Never>?
    private let watchPlanUseCase: WatchPlanUseCase

    init(watchPlanUseCase: WatchPlanUseCase = WatchPlanUseCase()) {
        self.watchPlanUseCase = watchPlanUseCase
    }

    var content: String {
        switch state {
        case .idle: ""
        case .watching(let content, _): content
        case .error(_, let prior): prior?.content ?? ""
        }
    }

    var phases: [PlanPhase] {
        switch state {
        case .idle: []
        case .watching(_, let phases): phases
        case .error(_, let prior): prior?.phases ?? []
        }
    }

    func startWatching(url: URL) {
        watchTask?.cancel()
        watchTask = Task {
            for await (content, phases) in watchPlanUseCase.stream(url: url) {
                self.state = .watching(content: content, phases: phases)
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
        state = .idle
    }
}
