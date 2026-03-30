import Foundation
import SkillScannerSDK
import UseCaseSDK

public struct ScanSkillsUseCase: UseCase {

    public struct Options: Sendable {
        public let query: String?
        public let workingDirectory: String

        public init(workingDirectory: String, query: String? = nil) {
            self.query = query
            self.workingDirectory = workingDirectory
        }
    }

    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func run(_ options: Options) throws -> [SkillInfo] {
        let repoURL = URL(filePath: options.workingDirectory)
        let skills = try scanner.scanSkills(at: repoURL)
        if let query = options.query, !query.isEmpty {
            return scanner.filterSkills(skills, query: query)
        }
        return skills
    }
}
