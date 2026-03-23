import ArchitecturePlannerService
import Foundation

extension ArchitecturePlannerStore {
    static func cliDirectoryURL(repoName: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ai-dev-tools")
            .appendingPathComponent(repoName)
            .appendingPathComponent("architecture-planner")
    }
}
