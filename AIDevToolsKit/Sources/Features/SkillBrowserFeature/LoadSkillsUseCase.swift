import Foundation
import RepositorySDK
import SkillScannerSDK

public struct LoadSkillsUseCase: Sendable {
    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func run(options: RepositoryInfo) async throws -> [SkillInfo] {
        let scanner = self.scanner
        return try await Task.detached {
            try scanner.scanSkills(at: options.path)
        }.value
    }
}
