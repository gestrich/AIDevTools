import ClaudeChainSDK
import ClaudeChainService
import Foundation

public struct ChainProject: Sendable {
    public let name: String
    public let specPath: String
    public let completedTasks: Int
    public let pendingTasks: Int
    public let totalTasks: Int

    public init(name: String, specPath: String, completedTasks: Int, pendingTasks: Int, totalTasks: Int) {
        self.name = name
        self.specPath = specPath
        self.completedTasks = completedTasks
        self.pendingTasks = pendingTasks
        self.totalTasks = totalTasks
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
            return ChainProject(
                name: project.name,
                specPath: absoluteProject.specPath,
                completedTasks: spec.completedTasks,
                pendingTasks: spec.pendingTasks,
                totalTasks: spec.totalTasks
            )
        }
    }
}
