import Foundation

public struct SweepBatchStats: Sendable {
    public let finalCursor: String?
    public let modifyingTasks: Int
    public let skipped: Int
    public let tasks: Int

    public init(finalCursor: String?, modifyingTasks: Int, skipped: Int, tasks: Int) {
        self.finalCursor = finalCursor
        self.modifyingTasks = modifyingTasks
        self.skipped = skipped
        self.tasks = tasks
    }
}
