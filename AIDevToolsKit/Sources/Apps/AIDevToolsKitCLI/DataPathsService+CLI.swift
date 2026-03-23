import DataPathsService
import Foundation

extension DataPathsService {
    static let cliDefaultRootPath = URL.homeDirectory.appending(path: "Desktop/ai-dev-tools")

    static func fromCLI(dataPath: String?) throws -> DataPathsService {
        let rootPath = dataPath.map { URL(filePath: $0) } ?? cliDefaultRootPath
        let service = try DataPathsService(rootPath: rootPath)
        try MigrateDataPathsUseCase(dataPathsService: service).run()
        return service
    }
}
