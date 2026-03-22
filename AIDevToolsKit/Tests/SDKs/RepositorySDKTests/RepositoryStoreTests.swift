import Foundation
import Testing
@testable import RepositorySDK

struct RepositoryStoreTests {
    private func makeTempStore() throws -> (RepositoryStore, URL) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        return (RepositoryStore(repositoriesFile: tempDir.appending(path: "repositories.json")), tempDir)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test func loadAllReturnsEmptyWhenNoFile() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }

        // Act
        let result = try store.loadAll()

        // Assert
        #expect(result.isEmpty)
    }

    @Test func saveAndLoadRoundTrip() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let repos = [
            RepositoryInfo(path: URL(filePath: "/tmp/repo1")),
            RepositoryInfo(
                path: URL(filePath: "/tmp/repo2"),
                name: "Custom Name",
                description: "A test repo",
                verification: Verification(commands: ["swift build"]),
                pullRequest: PullRequestConfig(baseBranch: "main", branchNamingConvention: "feature/<name>")
            ),
        ]

        // Act
        try store.save(repos)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 2)
        #expect(loaded[0].id == repos[0].id)
        #expect(loaded[0].name == "repo1")
        #expect(loaded[1].name == "Custom Name")
        #expect(loaded[1].description == "A test repo")
        #expect(loaded[1].verification?.commands == ["swift build"])
    }

    @Test func addAppendsRepository() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let first = RepositoryInfo(path: URL(filePath: "/tmp/repo1"))
        let second = RepositoryInfo(path: URL(filePath: "/tmp/repo2"))

        // Act
        try store.add(first)
        try store.add(second)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 2)
        #expect(loaded[0].id == first.id)
        #expect(loaded[1].id == second.id)
    }

    @Test func updateModifiesExistingRepository() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let original = RepositoryInfo(path: URL(filePath: "/tmp/repo1"), name: "Original")
        try store.add(original)

        var updated = original
        updated.description = "Updated description"

        // Act
        try store.update(updated)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 1)
        #expect(loaded[0].id == original.id)
        #expect(loaded[0].description == "Updated description")
    }

    @Test func removeDeletesById() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let first = RepositoryInfo(path: URL(filePath: "/tmp/repo1"))
        let second = RepositoryInfo(path: URL(filePath: "/tmp/repo2"))
        try store.save([first, second])

        // Act
        try store.remove(id: first.id)
        let loaded = try store.loadAll()

        // Assert
        #expect(loaded.count == 1)
        #expect(loaded[0].id == second.id)
    }

    @Test func findByID() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let repo = RepositoryInfo(path: URL(filePath: "/tmp/repo1"), name: "Target")
        let other = RepositoryInfo(path: URL(filePath: "/tmp/repo2"))
        try store.save([repo, other])

        // Act
        let found = try store.find(byID: repo.id)
        let notFound = try store.find(byID: UUID())

        // Assert
        #expect(found?.name == "Target")
        #expect(notFound == nil)
    }

    @Test func findByPath() throws {
        // Arrange
        let (store, tempDir) = try makeTempStore()
        defer { cleanup(tempDir) }
        let targetPath = URL(filePath: "/tmp/repo1")
        let repo = RepositoryInfo(path: targetPath, name: "Target")
        try store.save([repo])

        // Act
        let found = try store.find(byPath: targetPath)
        let notFound = try store.find(byPath: URL(filePath: "/nonexistent"))

        // Assert
        #expect(found?.name == "Target")
        #expect(notFound == nil)
    }
}
