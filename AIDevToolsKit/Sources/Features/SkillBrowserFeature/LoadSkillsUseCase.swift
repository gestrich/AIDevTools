import Foundation
import RepositorySDK
import SkillScannerSDK
import UseCaseSDK

public struct LoadSkillsUseCase: UseCase {
    private let scanner: SkillScanner
    private let globalCommandsDirectory: URL?
    private let globalSkillsDirectories: [URL]

    public init(
        scanner: SkillScanner = SkillScanner(),
        globalCommandsDirectory: URL? = SkillScanner.defaultGlobalCommandsDirectory,
        globalSkillsDirectories: [URL] = SkillScanner.defaultGlobalSkillsDirectories
    ) {
        self.scanner = scanner
        self.globalCommandsDirectory = globalCommandsDirectory
        self.globalSkillsDirectories = globalSkillsDirectories
    }

    public func run(options: RepositoryConfiguration) async throws -> [SkillInfo] {
        let scanner = self.scanner
        let globalCommandsDir = globalCommandsDirectory
        let globalSkillsDirs = globalSkillsDirectories
        return try await Task.detached {
            try scanner.scanSkills(
                at: options.path,
                globalCommandsDirectory: globalCommandsDir,
                globalSkillsDirectories: globalSkillsDirs
            )
        }.value
    }
}
