import Foundation
import RepositorySDK
import Testing
@testable import MarkdownPlannerService

struct MarkdownPlannerRepoSettingsStoreTests {
    private func makeTempStore() -> (MarkdownPlannerRepoSettingsStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        return (MarkdownPlannerRepoSettingsStore(repositoryStore: repositoryStore), tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
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

    @Test func updateInsertsNewSettings() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { cleanup(tempDir) }
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        let store = MarkdownPlannerRepoSettingsStore(repositoryStore: repositoryStore)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)

        // Act
        try store.update(repoId: repo.id, proposedDirectory: "plans/", completedDirectory: "done/")
        let found = try store.settings(forRepoId: repo.id)

        // Assert
        #expect(found?.proposedDirectory == "plans/")
        #expect(found?.completedDirectory == "done/")
    }

    @Test func updateModifiesExistingSettings() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { cleanup(tempDir) }
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        let store = MarkdownPlannerRepoSettingsStore(repositoryStore: repositoryStore)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)
        try store.update(repoId: repo.id, proposedDirectory: "old/proposed", completedDirectory: "old/completed")

        // Act
        try store.update(repoId: repo.id, proposedDirectory: "new/proposed", completedDirectory: "new/completed")
        let found = try store.settings(forRepoId: repo.id)

        // Assert
        #expect(found?.proposedDirectory == "new/proposed")
        #expect(found?.completedDirectory == "new/completed")
    }

    @Test func removeDeletesSettings() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { cleanup(tempDir) }
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        let store = MarkdownPlannerRepoSettingsStore(repositoryStore: repositoryStore)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)
        try store.update(repoId: repo.id, proposedDirectory: "path1", completedDirectory: nil)

        // Act
        try store.remove(repoId: repo.id)
        let found = try store.settings(forRepoId: repo.id)

        // Assert
        #expect(found == nil)
    }

    @Test func updateWithNilDirectories() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { cleanup(tempDir) }
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        let store = MarkdownPlannerRepoSettingsStore(repositoryStore: repositoryStore)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)

        // Act
        try store.update(repoId: repo.id, proposedDirectory: nil, completedDirectory: nil)
        let found = try store.settings(forRepoId: repo.id)

        // Assert
        #expect(found != nil)
        #expect(found?.proposedDirectory == nil)
        #expect(found?.completedDirectory == nil)
    }

    @Test func resolvedProposedDirectoryAbsolutePath() {
        // Arrange
        let settings = MarkdownPlannerRepoSettings(proposedDirectory: "/absolute/proposed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedProposedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/absolute/proposed")
    }

    @Test func resolvedProposedDirectoryRelativePath() {
        // Arrange
        let settings = MarkdownPlannerRepoSettings(proposedDirectory: "specs/proposed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedProposedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/tmp/repo/specs/proposed")
    }

    @Test func resolvedCompletedDirectoryAbsolutePath() {
        // Arrange
        let settings = MarkdownPlannerRepoSettings(completedDirectory: "/absolute/completed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCompletedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/absolute/completed")
    }

    @Test func resolvedCompletedDirectoryRelativePath() {
        // Arrange
        let settings = MarkdownPlannerRepoSettings(completedDirectory: "specs/completed")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCompletedDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/tmp/repo/specs/completed")
    }

    @Test func resolvedDirectoriesUseDefaultsWhenNil() {
        // Arrange
        let settings = MarkdownPlannerRepoSettings()
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let proposed = settings.resolvedProposedDirectory(repoPath: repoPath)
        let completed = settings.resolvedCompletedDirectory(repoPath: repoPath)

        // Assert
        #expect(proposed.path(percentEncoded: false) == "/tmp/repo/docs/proposed")
        #expect(completed.path(percentEncoded: false) == "/tmp/repo/docs/completed")
    }
}
