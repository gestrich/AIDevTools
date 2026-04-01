import Foundation
import RepositorySDK
import SkillScannerSDK
import UseCaseSDK

public struct LoadSkillsUseCase: UseCase {
    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func run(options: RepositoryConfiguration) async throws -> [SkillInfo] {
        let scanner = self.scanner
        return try await Task.detached {
            try scanner.scanSkills(at: options.path)
        }.value
    }
}
