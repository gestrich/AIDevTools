import Foundation
import Testing
@testable import PlanRunnerService

struct PlanRepoSettingsStoreTests {
    private func makeTempStore() -> (PlanRepoSettingsStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (PlanRepoSettingsStore(filePath: tempDir.appending(path: "plan-settings.json")), tempDir)
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
        let settings = [PlanRepoSettings(
            repoId: repoId,
            proposedDirectory: "specs/proposed",
            completedDirectory: "specs/completed"
        )]

        // Act
        try store.save(settings)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 1)
        #expect(loaded[0].repoId == repoId)
        #expect(loaded[0].proposedDirectory == "specs/proposed")
        #expect(loaded[0].completedDirectory == "specs/completed")
    }

    @Test func updateInsertsNewSettings() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId = UUID()

        // Act
        try store.update(repoId: repoId, proposedDirectory: "plans/", completedDirectory: "done/")
        let found = try store.settings(forRepoId: repoId)

        // Assert
        #expect(found?.proposedDirectory == "plans/")
        #expect(found?.completedDirectory == "done/")
    }

    @Test func updateModifiesExistingSettings() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId = UUID()
        try store.update(repoId: repoId, proposedDirectory: "old/proposed", completedDirectory: "old/completed")

        // Act
        try store.update(repoId: repoId, proposedDirectory: "new/proposed", completedDirectory: "new/completed")
        let found = try store.settings(forRepoId: repoId)

        // Assert
        #expect(found?.proposedDirectory == "new/proposed")
        #expect(found?.completedDirectory == "new/completed")
        #expect(try store.loadAll().count == 1)
    }

    @Test func removeDeletesByRepoId() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId1 = UUID()
        let repoId2 = UUID()
        try store.update(repoId: repoId1, proposedDirectory: "path1", completedDirectory: nil)
        try store.update(repoId: repoId2, proposedDirectory: "path2", completedDirectory: nil)

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

    @Test func resolvedProposedDirectoryAbsolutePath() {
        // Arrange
        let settings = PlanRepoSettings(repoId: UUID(), proposedDirectory: "/absolute/proposed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedProposedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/absolute/proposed")
    }

    @Test func resolvedProposedDirectoryRelativePath() {
        // Arrange
        let settings = PlanRepoSettings(repoId: UUID(), proposedDirectory: "specs/proposed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedProposedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/tmp/repo/specs/proposed")
    }

    @Test func resolvedCompletedDirectoryAbsolutePath() {
        // Arrange
        let settings = PlanRepoSettings(repoId: UUID(), completedDirectory: "/absolute/completed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCompletedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/absolute/completed")
    }

    @Test func resolvedCompletedDirectoryRelativePath() {
        // Arrange
        let settings = PlanRepoSettings(repoId: UUID(), completedDirectory: "specs/completed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCompletedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/tmp/repo/specs/completed")
    }

    @Test func resolvedDirectoriesUseDefaultsWhenNil() {
        // Arrange
        let settings = PlanRepoSettings(repoId: UUID())
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let proposed = settings.resolvedProposedDirectory(repoPath: repoPath)
        let completed = settings.resolvedCompletedDirectory(repoPath: repoPath)

        // Assert
        #expect(proposed.path(percentEncoded: false) == "/tmp/repo/docs/proposed")
        #expect(completed.path(percentEncoded: false) == "/tmp/repo/docs/completed")
    }

    @Test func updateWithNilDirectories() throws {
        // Arrange
        let (store, tempDir) = makeTempStore()
        defer { cleanup(tempDir) }
        let repoId = UUID()

        // Act
        try store.update(repoId: repoId, proposedDirectory: nil, completedDirectory: nil)
        let found = try store.settings(forRepoId: repoId)

        // Assert
        #expect(found != nil)
        #expect(found?.proposedDirectory == nil)
        #expect(found?.completedDirectory == nil)
    }
}
