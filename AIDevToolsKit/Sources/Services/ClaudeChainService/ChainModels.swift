import Foundation

public struct ChainProject: Hashable, Sendable {
    public let completedTasks: Int
    public let isGitHubOnly: Bool
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
        isGitHubOnly: Bool = false
    ) {
        self.completedTasks = completedTasks
        self.isGitHubOnly = isGitHubOnly
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
