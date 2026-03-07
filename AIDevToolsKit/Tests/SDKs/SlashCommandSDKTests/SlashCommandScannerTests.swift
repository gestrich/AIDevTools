import Foundation
import Testing
@testable import SlashCommandSDK

struct SlashCommandScannerTests {
    private func makeTempDir(files: [String] = []) throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let commandsDir = dir.appendingPathComponent(".claude/commands")
        try FileManager.default.createDirectory(at: commandsDir, withIntermediateDirectories: true)
        for file in files {
            let filePath = commandsDir.appendingPathComponent(file)
            let parentDir = filePath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try "# Command content".write(to: filePath, atomically: true, encoding: .utf8)
        }
        return dir.path
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - scanCommands

    @Test func scanFindsMarkdownFiles() throws {
        // Arrange
        let dir = try makeTempDir(files: ["commit.md", "review.md"])
        defer { cleanup(dir) }
        let scanner = SlashCommandScanner()

        // Act
        let commands = scanner.scanCommands(workingDirectory: dir)

        // Assert
        #expect(commands.count >= 2)
        let names = commands.map(\.name)
        #expect(names.contains("/commit"))
        #expect(names.contains("/review"))
    }

    @Test func scanIgnoresNonMarkdownFiles() throws {
        // Arrange
        let dir = try makeTempDir(files: ["command.md", "readme.txt", "data.json"])
        defer { cleanup(dir) }
        let scanner = SlashCommandScanner()

        // Act
        let commands = scanner.scanCommands(workingDirectory: dir)
        let localNames = commands.filter { $0.path.contains(dir) }.map(\.name)

        // Assert
        #expect(localNames.count == 1)
        #expect(localNames.contains("/command"))
    }

    @Test func scanHandlesMissingDirectory() throws {
        // Arrange
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let scanner = SlashCommandScanner()

        // Act
        let commands = scanner.scanCommands(workingDirectory: dir)

        // Assert — should not crash, may return global commands
        #expect(commands.count >= 0)
    }

    @Test func scanReturnsSortedByName() throws {
        // Arrange
        let dir = try makeTempDir(files: ["zebra.md", "alpha.md", "middle.md"])
        defer { cleanup(dir) }
        let scanner = SlashCommandScanner()

        // Act
        let commands = scanner.scanCommands(workingDirectory: dir)
        let localNames = commands.filter { $0.path.contains(dir) }.map(\.name)

        // Assert
        #expect(localNames == localNames.sorted())
    }

    // MARK: - filterCommands

    @Test func filterReturnsAllCommandsForEmptyQuery() {
        // Arrange
        let scanner = SlashCommandScanner()
        let commands = [
            SlashCommand(name: "/commit", path: "/path/commit.md"),
            SlashCommand(name: "/review", path: "/path/review.md"),
        ]

        // Act
        let result = scanner.filterCommands(commands, query: "")

        // Assert
        #expect(result.count == 2)
    }

    @Test func filterMatchesPrefixWithSlash() {
        // Arrange
        let scanner = SlashCommandScanner()
        let commands = [
            SlashCommand(name: "/commit", path: "/path/commit.md"),
            SlashCommand(name: "/review", path: "/path/review.md"),
        ]

        // Act
        let result = scanner.filterCommands(commands, query: "/com")

        // Assert
        #expect(result.count == 1)
        #expect(result.first?.name == "/commit")
    }

    @Test func filterMatchesPrefixWithoutSlash() {
        // Arrange
        let scanner = SlashCommandScanner()
        let commands = [
            SlashCommand(name: "/commit", path: "/path/commit.md"),
            SlashCommand(name: "/review", path: "/path/review.md"),
        ]

        // Act
        let result = scanner.filterCommands(commands, query: "rev")

        // Assert
        #expect(result.count == 1)
        #expect(result.first?.name == "/review")
    }

    @Test func filterReturnsEmptyForNoMatch() {
        // Arrange
        let scanner = SlashCommandScanner()
        let commands = [
            SlashCommand(name: "/commit", path: "/path/commit.md"),
        ]

        // Act
        let result = scanner.filterCommands(commands, query: "/xyz")

        // Assert
        #expect(result.isEmpty)
    }
}
