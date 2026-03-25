import Foundation
import Testing
@testable import EvalService

struct EvalRepoSettingsStoreTests {
    private func makeTempStore() -> (EvalRepoSettingsStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (EvalRepoSettingsStore(filePath: tempDir.appending(path: "eval-settings.json")), tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func loadAllReturnsEmptyWhenNoFile() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Act
        let result = try store.loadAll()

        // Assert
        #expect(result.isEmpty)
    }

    @Test func saveAndLoadRoundTrip() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId = UUID()
        let settings = [EvalRepoSettings(repoId: repoId, casesDirectory: "evals/cases")]

        // Act
        try store.save(settings)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 1)
        #expect(loaded[0].repoId == repoId)
        #expect(loaded[0].casesDirectory == "evals/cases")
    }

    @Test func updateInsertsNewSettings() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId = UUID()

        // Act
        try store.update(repoId: repoId, casesDirectory: "/tmp/cases")
        let found = try store.settings(forRepoId: repoId)

        // Assert
        #expect(found?.casesDirectory == "/tmp/cases")
    }

    @Test func updateModifiesExistingSettings() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId = UUID()
        try store.update(repoId: repoId, casesDirectory: "old/path")

        // Act
        try store.update(repoId: repoId, casesDirectory: "new/path")
        let found = try store.settings(forRepoId: repoId)

        // Assert
        #expect(found?.casesDirectory == "new/path")
        #expect(try store.loadAll().count == 1)
    }

    @Test func removeDeletesByRepoId() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId1 = UUID()
        let repoId2 = UUID()
        try store.update(repoId: repoId1, casesDirectory: "path1")
        try store.update(repoId: repoId2, casesDirectory: "path2")

        // Act
        try store.remove(repoId: repoId1)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 1)
        #expect(loaded[0].repoId == repoId2)
    }

    @Test func settingsForRepoIdReturnsNilWhenNotFound() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }

        // Act
        let result = try store.settings(forRepoId: UUID())

        // Assert
        #expect(result == nil)
    }

    @Test func resolvedCasesDirectoryAbsolutePath() {
        // Arrange
        let settings = EvalRepoSettings(repoId: UUID(), casesDirectory: "/absolute/cases")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCasesDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/absolute/cases")
    }

    @Test func resolvedCasesDirectoryRelativePath() {
        // Arrange
        let settings = EvalRepoSettings(repoId: UUID(), casesDirectory: "evals/cases")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCasesDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/tmp/repo/evals/cases")
    }
}
