#if canImport(SwiftData)
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
        let baseDir = try service.path(for: .architecturePlanner)
        let archDir = baseDir.appendingPathComponent(repoName)
        try FileManager.default.createDirectory(at: archDir, withIntermediateDirectories: true, attributes: nil)
        return try ArchitecturePlannerStore(directoryURL: archDir)
    }
}
#endif
