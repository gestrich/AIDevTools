public enum ServicePath {
    case anthropicSessions
    case architecturePlanner
    case evalsOutput(String)
    case github(repoSlug: String)
    case prradarOutput(String)
    case repositories
    case worktrees(feature: String)

    var relativePath: String {
        switch self {
        case .anthropicSessions:
            return "sdks/anthropic/sessions"
        case .architecturePlanner:
            return "services/architecture-planner"
        case .evalsOutput(let repoName):
            return "services/evals/\(repoName)"
        case .github(let repoSlug):
            return "services/github/\(repoSlug)"
        case .prradarOutput(let repoName):
            return "services/pr-radar/repos/\(repoName)"
        case .repositories:
            return "services/repositories"
        case .worktrees(let feature):
            return "services/\(feature)/worktrees"
        }
    }
}

public extension ServicePath {
    static var claudeChainWorktrees: ServicePath { .worktrees(feature: "claude-chain") }
    static var planWorktrees: ServicePath { .worktrees(feature: "plan") }
}
