public enum ServicePath {
    case architecturePlanner
    case evalSettings
    case github(repoSlug: String)
    case planSettings
    case prradarOutput(String)
    case prradarSettings
    case repoOutput(String)
    case repositories

    var relativePath: String {
        switch self {
        case .architecturePlanner:
            return "architecture-planner"
        case .evalSettings:
            return "eval/settings"
        case .github(let repoSlug):
            return "github/\(repoSlug)"
        case .planSettings:
            return "plan/settings"
        case .prradarOutput(let repoName):
            return "prradar/repos/\(repoName)"
        case .prradarSettings:
            return "prradar/settings"
        case .repoOutput(let repoName):
            return "repos/\(repoName)"
        case .repositories:
            return "repositories"
        }
    }
}
