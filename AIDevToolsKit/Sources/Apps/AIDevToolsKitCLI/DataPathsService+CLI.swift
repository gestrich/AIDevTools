import ArchitecturePlannerService
import DataPathsService
import Foundation

extension DataPathsService {
    static func fromCLI(dataPath: String?) throws -> DataPathsService {
        let resolved = ResolveDataPathUseCase().resolve(explicit: dataPath)
        let service = try DataPathsService(rootPath: resolved.path)
        try MigrateDataPathsUseCase(dataPathsService: service).run()
        return service
    }

    static func makeArchPlannerStore(dataPath: String?, repoName: String) throws -> ArchitecturePlannerStore {
        let service = try fromCLI(dataPath: dataPath)
        let archDir = try service.path(for: "architecture-planner", subdirectory: repoName)
        return try ArchitecturePlannerStore(directoryURL: archDir)
    }
}
