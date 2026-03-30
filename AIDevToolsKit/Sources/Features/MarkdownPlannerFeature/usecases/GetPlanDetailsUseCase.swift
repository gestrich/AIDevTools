import Foundation
import MarkdownPlannerService

public struct GetPlanDetailsUseCase: Sendable {

    public enum GetPlanDetailsError: LocalizedError {
        case planNotFound(String)
        case contentUnreadable(String)

        public var errorDescription: String? {
            switch self {
            case .planNotFound(let name):
                return "Plan not found: \(name)"
            case .contentUnreadable(let name):
                return "Unable to read content for plan: \(name)"
            }
        }
    }

    private let loadPlans: LoadPlansUseCase

    public init(proposedDirectory: URL) {
        self.loadPlans = LoadPlansUseCase(proposedDirectory: proposedDirectory)
    }

    public func run(planName: String) async throws -> String {
        let plans = await loadPlans.run()
        guard let plan = plans.first(where: { $0.name == planName }) else {
            throw GetPlanDetailsError.planNotFound(planName)
        }
        guard let content = try? String(contentsOf: plan.planURL, encoding: .utf8) else {
            throw GetPlanDetailsError.contentUnreadable(planName)
        }
        return content
    }
}
