import Foundation
import SkillScannerSDK

public struct ScanSkillsUseCase: Sendable {

    public struct Options: Sendable {
        public let workingDirectory: String
        public let query: String?

        public init(workingDirectory: String, query: String? = nil) {
            self.workingDirectory = workingDirectory
            self.query = query
        }
    }

    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func run(_ options: Options) throws -> [SkillInfo] {
        let repoURL = URL(filePath: options.workingDirectory)
        let globalCommandsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/commands")
        let skills = try scanner.scanSkills(at: repoURL, globalCommandsDirectory: globalCommandsDir)
        if let query = options.query, !query.isEmpty {
            return scanner.filterSkills(skills, query: query)
        }
        return skills
    }
}
