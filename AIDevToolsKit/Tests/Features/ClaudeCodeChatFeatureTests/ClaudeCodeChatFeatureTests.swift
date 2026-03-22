import Foundation
import Testing
@testable import ClaudeCodeChatFeature
@testable import SkillScannerSDK

struct ScanSkillsUseCaseTests {

    @Test func runReturnsSkillsForDirectory() throws {
        // Arrange
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let commandsDir = dir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        try "# Test".write(to: commandsDir.appendingPathComponent("test.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let useCase = ScanSkillsUseCase()

        // Act
        let skills = try useCase.run(.init(workingDirectory: dir.path))

        // Assert
        let localSkills = skills.filter { $0.path.path().contains(dir.path) }
        #expect(localSkills.count == 1)
        #expect(localSkills.first?.name == "test")
    }

    @Test func runWithQueryFiltersResults() throws {
        // Arrange
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let commandsDir = dir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        try "# A".write(to: commandsDir.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
        try "# B".write(to: commandsDir.appendingPathComponent("beta.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let useCase = ScanSkillsUseCase()

        // Act
        let skills = try useCase.run(.init(workingDirectory: dir.path, query: "/alp"))

        // Assert
        let localSkills = skills.filter { $0.path.path().contains(dir.path) }
        #expect(localSkills.count == 1)
        #expect(localSkills.first?.name == "alpha")
    }

    @Test func runHandlesMissingDirectory() throws {
        // Arrange
        let useCase = ScanSkillsUseCase()
        let fakePath = "/tmp/\(UUID().uuidString)"

        // Act
        let skills = try useCase.run(.init(workingDirectory: fakePath))

        // Assert — should not crash
        #expect(skills.count >= 0)
    }
}
