import Foundation

public struct ChainProject: Hashable, Sendable {
    public let baseBranch: String
    public let branchPrefix: String
    public let completedTasks: Int
    public let isGitHubOnly: Bool
    public let kindBadge: String?
    public let maxOpenPRs: Int?
    public let name: String
    public let pendingTasks: Int
    public let specPath: String
    public let tasks: [ChainTask]
    public let totalTasks: Int

    public init(
        name: String,
        specPath: String,
        tasks: [ChainTask] = [],
        completedTasks: Int,
        pendingTasks: Int,
        totalTasks: Int,
        baseBranch: String = "main",
        branchPrefix: String? = nil,
        isGitHubOnly: Bool = false,
        kindBadge: String? = nil,
        maxOpenPRs: Int? = nil
    ) {
        self.baseBranch = baseBranch
        self.branchPrefix = branchPrefix ?? "claude-chain-\(name)-"
        self.completedTasks = completedTasks
        self.isGitHubOnly = isGitHubOnly
        self.kindBadge = kindBadge
        self.maxOpenPRs = maxOpenPRs
        self.name = name
        self.pendingTasks = pendingTasks
        self.specPath = specPath
        self.tasks = tasks
        self.totalTasks = totalTasks
    }
}

public struct ChainTask: Hashable, Identifiable, Sendable {
    public let description: String
    public var id: Int { index }
    public let index: Int
    public let isCompleted: Bool

    public init(index: Int, description: String, isCompleted: Bool) {
        self.description = description
        self.index = index
        self.isCompleted = isCompleted
    }
}
