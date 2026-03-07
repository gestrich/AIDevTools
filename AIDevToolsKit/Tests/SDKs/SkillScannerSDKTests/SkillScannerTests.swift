import Foundation
import Testing
@testable import SkillScannerSDK

struct SkillScannerTests {
    private func makeTempRepo(skillFiles: [String], directory: String = ".claude/skills") throws -> URL {
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir.appendingPathComponent(directory)
        try FileManager.default.createDirectory(at: skillsDir, withIntermediateDirectories: true)
        for file in skillFiles {
            let filePath = skillsDir.appendingPathComponent(file)
            try "# Skill content".write(to: filePath, atomically: true, encoding: .utf8)
        }
        return repoDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func scanFindsMarkdownFiles() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["commit.md", "review.md"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.count == 2)
        #expect(skills[0].name == "commit")
        #expect(skills[1].name == "review")
    }

    @Test func scanIgnoresNonMarkdownFiles() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["skill.md", "readme.txt", "data.json"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "skill")
    }

    @Test func scanReturnsEmptyWhenNoSkillsDirectory() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: repoDir, withIntermediateDirectories: true)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.isEmpty)
    }

    @Test func scanReturnsSortedByName() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["zebra.md", "alpha.md", "middle.md"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.map(\.name) == ["alpha", "middle", "zebra"])
    }

    @Test func scanFindsSubdirectories() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
        let subdir = skillsDir.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "# Skill".write(to: subdir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "my-skill")
        #expect(skills[0].path.standardizedFileURL == subdir.standardizedFileURL)
    }

    @Test func scanFindsReferenceFilesInSubdirectory() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let skillsDir = repoDir
            .appendingPathComponent(".claude")
            .appendingPathComponent("skills")
        let subdir = skillsDir.appendingPathComponent("my-skill")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)
        try "# Main skill".write(to: subdir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
        try "# Guide".write(to: subdir.appendingPathComponent("guide.md"), atomically: true, encoding: .utf8)
        try "# Examples".write(to: subdir.appendingPathComponent("examples.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].referenceFiles.count == 2)
        #expect(skills[0].referenceFiles[0].name == "examples")
        #expect(skills[0].referenceFiles[1].name == "guide")
    }

    @Test func scanFindsSkillsInAgentsDirectory() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["deploy.md"], directory: ".agents/skills")
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].name == "deploy")
    }

    @Test func agentsSkillsPreferredOverClaudeSkills() throws {
        // Arrange
        let repoDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let agentsDir = repoDir.appendingPathComponent(".agents/skills")
        let claudeDir = repoDir.appendingPathComponent(".claude/skills")
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try "# Agents version".write(to: agentsDir.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        try "# Claude version".write(to: claudeDir.appendingPathComponent("shared.md"), atomically: true, encoding: .utf8)
        try "# Claude only".write(to: claudeDir.appendingPathComponent("claude-only.md"), atomically: true, encoding: .utf8)
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.count == 2)
        #expect(skills.map(\.name) == ["claude-only", "shared"])
        let shared = skills.first(where: { $0.name == "shared" })!
        #expect(shared.path.path.contains(".agents/skills"))
    }

    @Test func standaloneMarkdownHasNoReferenceFiles() throws {
        // Arrange
        let repoDir = try makeTempRepo(skillFiles: ["commit.md"])
        defer { cleanup(repoDir) }
        let scanner = SkillScanner()

        // Act
        let skills = try scanner.scanSkills(at: repoDir)

        // Assert
        #expect(skills.count == 1)
        #expect(skills[0].referenceFiles.isEmpty)
    }
}
