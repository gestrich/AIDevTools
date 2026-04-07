public enum ServicePath {
    case architecturePlanner
    case github(repoSlug: String)
    case prradarOutput(String)
    case repoOutput(String)
    case repositories
    case worktrees(feature: String)

    var relativePath: String {
        switch self {
        case .architecturePlanner:
            return "architecture-planner"
        case .github(let repoSlug):
            return "github/\(repoSlug)"
        case .prradarOutput(let repoName):
            return "prradar/repos/\(repoName)"
        case .repoOutput(let repoName):
            return "repos/\(repoName)"
        case .repositories:
            return "repositories"
        case .worktrees(let feature):
            return "\(feature)/worktrees"
        }
    }
}

public extension ServicePath {
    static var claudeChainWorktrees: ServicePath { .worktrees(feature: "claude-chain") }
    static var planWorktrees: ServicePath { .worktrees(feature: "plan") }
}
