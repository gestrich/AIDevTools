import Foundation

public struct MarkdownPlanEntry: Identifiable, Sendable {
    public var id: String { planURL.path }
    public let planURL: URL
    public let completedPhases: Int
    public let totalPhases: Int
    public let creationDate: Date?

    public var name: String { planURL.deletingPathExtension().lastPathComponent }
    public var isFullyCompleted: Bool { totalPhases > 0 && completedPhases == totalPhases }

    public func relativePath(to repoPath: URL) -> String {
        let repo = repoPath.path(percentEncoded: false)
        let plan = planURL.path(percentEncoded: false)
        if plan.hasPrefix(repo) {
            return String(plan.dropFirst(repo.count).drop(while: { $0 == "/" }))
        }
        return plan
    }

    public init(planURL: URL, completedPhases: Int, totalPhases: Int, creationDate: Date?) {
        self.planURL = planURL
        self.completedPhases = completedPhases
        self.totalPhases = totalPhases
        self.creationDate = creationDate
    }
}
