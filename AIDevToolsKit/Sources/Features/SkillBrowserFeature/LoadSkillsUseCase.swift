import Foundation
import RepositorySDK
import SkillService
import SkillScannerSDK

public struct LoadSkillsUseCase: Sendable {
    private let scanner: SkillScanner

    public init(scanner: SkillScanner = SkillScanner()) {
        self.scanner = scanner
    }

    public func run(options: RepositoryInfo) async throws -> [Skill] {
        let scanner = self.scanner
        return try await Task.detached {
            try scanner.scanSkills(at: options.path).map { info in
                Skill(
                    name: info.name,
                    path: info.path,
                    referenceFiles: info.referenceFiles.map { ref in
                        ReferenceFile(name: ref.name, url: ref.url)
                    },
                    source: info.source
                )
            }
        }.value
    }
}
