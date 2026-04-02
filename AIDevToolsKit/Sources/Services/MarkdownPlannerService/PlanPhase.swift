import Foundation

public struct PlanPhase: Identifiable, Sendable {
    public var id: Int { index }
    public let index: Int
    public let description: String
    public let isCompleted: Bool

    public init(index: Int, description: String, isCompleted: Bool) {
        self.index = index
        self.description = description
        self.isCompleted = isCompleted
    }

    public static func parsePhases(from content: String) -> [PlanPhase] {
        var phases: [PlanPhase] = []
        var index = 0
        for line in content.components(separatedBy: "\n") {
            if line.hasPrefix("## - [x] ") {
                let desc = String(line.dropFirst("## - [x] ".count))
                phases.append(PlanPhase(index: index, description: desc, isCompleted: true))
                index += 1
            } else if line.hasPrefix("## - [ ] ") {
                let desc = String(line.dropFirst("## - [ ] ".count))
                phases.append(PlanPhase(index: index, description: desc, isCompleted: false))
                index += 1
            }
        }
        return phases
    }
}
