import Foundation
import RepositorySDK
import Testing
@testable import EvalService

struct EvalRepoSettingsStoreTests {
    private func makeTempStore() -> (EvalRepoSettingsStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        return (EvalRepoSettingsStore(repositoryStore: repositoryStore), tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func addRepo(to store: EvalRepoSettingsStore) throws -> RepositoryConfiguration {
        let repoFile = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)
        return repo
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
        let store = EvalRepoSettingsStore(repositoryStore: repositoryStore)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)

        // Act
        try store.update(repoId: repo.id, casesDirectory: "/tmp/cases")
        let found = try store.settings(forRepoId: repo.id)

        // Assert
        #expect(found?.casesDirectory == "/tmp/cases")
    }

    @Test func updateModifiesExistingSettings() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { cleanup(tempDir) }
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        let store = EvalRepoSettingsStore(repositoryStore: repositoryStore)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)
        try store.update(repoId: repo.id, casesDirectory: "old/path")

        // Act
        try store.update(repoId: repo.id, casesDirectory: "new/path")
        let found = try store.settings(forRepoId: repo.id)

        // Assert
        #expect(found?.casesDirectory == "new/path")
    }

    @Test func removeDeletesSettings() throws {
        // Arrange
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { cleanup(tempDir) }
        let repoFile = tempDir.appending(path: "repositories.json")
        let repositoryStore = RepositoryStore(repositoriesFile: repoFile)
        let store = EvalRepoSettingsStore(repositoryStore: repositoryStore)
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))
        try repositoryStore.add(repo)
        try store.update(repoId: repo.id, casesDirectory: "path1")

        // Act
        try store.remove(repoId: repo.id)
        let found = try store.settings(forRepoId: repo.id)

        // Assert
        #expect(found == nil)
    }

    @Test func resolvedCasesDirectoryAbsolutePath() {
        // Arrange
        let settings = EvalRepoSettings(casesDirectory: "/absolute/cases")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCasesDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/absolute/cases")
    }

    @Test func resolvedCasesDirectoryRelativePath() {
        // Arrange
        let settings = EvalRepoSettings(casesDirectory: "evals/cases")
        let repoPath = URL(filePath: "/tmp/repo")

        // Act
        let resolved = settings.resolvedCasesDirectory(repoPath: repoPath)

        // Assert
        #expect(resolved.path(percentEncoded: false) == "/tmp/repo/evals/cases")
    }
}
