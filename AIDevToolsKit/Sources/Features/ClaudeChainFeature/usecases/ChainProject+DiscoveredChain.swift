import ClaudeChainService
import Foundation

extension ChainProject {
    static func fromDiscoveredChain(_ discovered: DiscoveredChain) -> ChainProject {
        ChainProject(
            name: discovered.projectName,
            specPath: "",
            tasks: [],
            completedTasks: 0,
            pendingTasks: discovered.openPRCount,
            totalTasks: discovered.openPRCount,
            isGitHubOnly: true
        )
    }
}
