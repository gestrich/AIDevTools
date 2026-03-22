import Foundation
import Testing
@testable import RepositorySDK
@testable import SkillBrowserFeature

struct LoadSkillsUseCaseTests {
    private func makeTempRepo(skillFiles: [String]) throws -> URL {
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        for file in skillFiles {
            let filePath = skillsDir.appendingPathComponent(file)
            try "# Skill".write(to: filePath, atomically: true, encoding: .utf8)
        }
        return repoDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func loadSkillsMapsToSkillType() async throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["deploy.md", "test.md"])
        defer { cleanup(repoDir) }
        let useCase = LoadSkillsUseCase()
        let config = RepositoryInfo(path: repoDir)

        // Act
        let skills = try await useCase.run(options: config)

        // Assert
        #expect(skills.count == 2)
        #expect(skills[0].name == "deploy")
        #expect(skills[1].name == "test")
        #expect(skills[0].path.pathExtension == "md")
    }

    @Test func loadSkillsReturnsEmptyForRepoWithoutSkills() async throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { cleanup(repoDir) }
        let useCase = LoadSkillsUseCase()
        let config = RepositoryInfo(path: repoDir)

        // Act
        let skills = try await useCase.run(options: config)

        // Assert
        #expect(skills.isEmpty)
    }
}
