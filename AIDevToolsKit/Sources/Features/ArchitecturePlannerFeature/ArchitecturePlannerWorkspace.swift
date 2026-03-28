import AIOutputSDK
import ArchitecturePlannerService
import DataPathsService
import Foundation

public struct ArchitecturePlannerWorkspace {
    public let outputStore: AIOutputStore
    public let plannerStore: ArchitecturePlannerStore

    public init(dataPathsService: DataPathsService, repoName: String) throws {
        let directoryURL = try dataPathsService.path(for: "architecture-planner", subdirectory: repoName)
        self.outputStore = AIOutputStore(baseDirectory: directoryURL.appendingPathComponent("output"))
        self.plannerStore = try ArchitecturePlannerStore(directoryURL: directoryURL)
    }
}
