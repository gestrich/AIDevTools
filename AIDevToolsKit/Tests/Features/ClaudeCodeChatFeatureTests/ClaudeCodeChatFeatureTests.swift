import Foundation
import Testing
@testable import ClaudeCodeChatFeature
@testable import SlashCommandSDK

struct ScanSlashCommandsUseCaseTests {

    @Test func runReturnsCommandsForDirectory() throws {
        // Arrange
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let commandsDir = dir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        try "# Test".write(to: commandsDir.appendingPathComponent("test.md"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: dir) }

        let useCase = ScanSlashCommandsUseCase()

        // Act
        let commands = useCase.run(.init(workingDirectory: dir.path))

        // Assert
        let localCommands = commands.filter { $0.path.contains(dir.path) }
        #expect(localCommands.count == 1)
        #expect(localCommands.first?.name == "/test")
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

        let useCase = ScanSlashCommandsUseCase()

        // Act
        let commands = useCase.run(.init(workingDirectory: dir.path, query: "/alp"))

        // Assert
        let localCommands = commands.filter { $0.path.contains(dir.path) }
        #expect(localCommands.count == 1)
        #expect(localCommands.first?.name == "/alpha")
    }

    @Test func runHandlesMissingDirectory() {
        // Arrange
        let useCase = ScanSlashCommandsUseCase()
        let fakePath = "/tmp/\(UUID().uuidString)"

        // Act
        let commands = useCase.run(.init(workingDirectory: fakePath))

        // Assert — should not crash
        #expect(commands.count >= 0)
    }
}
