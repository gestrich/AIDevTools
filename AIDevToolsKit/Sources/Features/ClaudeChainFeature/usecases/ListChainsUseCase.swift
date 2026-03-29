import ClaudeChainSDK
import ClaudeChainService
import Foundation

public struct ChainProject: Hashable, Sendable {
    public let completedTasks: Int
    public let name: String
    public let pendingTasks: Int
    public let specPath: String
    public let tasks: [ChainTask]
    public let totalTasks: Int

    public init(name: String, specPath: String, tasks: [ChainTask] = [], completedTasks: Int, pendingTasks: Int, totalTasks: Int) {
        self.completedTasks = completedTasks
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

public struct ListChainsUseCase: Sendable {

    public struct Options: Sendable {
        public let repoPath: URL

        public init(repoPath: URL) {
            self.repoPath = repoPath
        }
    }

    public init() {}

    public func run(options: Options) throws -> [ChainProject] {
        let chainDir = options.repoPath.appendingPathComponent("claude-chain").path
        let projects = Project.findAll(baseDir: chainDir)

        return projects.compactMap { project in
            let absoluteProject = Project(
                name: project.name,
                basePath: (chainDir as NSString).appendingPathComponent(project.name)
            )
            let repository = ProjectRepository(repo: "")
            guard let spec = try? repository.loadLocalSpec(project: absoluteProject) else {
                return nil
            }
            let tasks = spec.tasks.map { specTask in
                ChainTask(
                    index: specTask.index,
                    description: specTask.description,
                    isCompleted: specTask.isCompleted
                )
            }
            return ChainProject(
                name: project.name,
                specPath: absoluteProject.specPath,
                tasks: tasks,
                completedTasks: spec.completedTasks,
                pendingTasks: spec.pendingTasks,
                totalTasks: spec.totalTasks
            )
        }
    }
}
