import Foundation
import Testing
@testable import PRRadarModelsService

@Suite("PRMetadata")
struct PRMetadataTests {

    // MARK: - toPRMetadata conversion

    @Test("converts required fields from GitHubPullRequest")
    func toPRMetadataRequiredFields() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 10,
            title: "Feature",
            state: "open",
            baseRefName: "main",
            headRefName: "feature/x",
            createdAt: "2025-03-01T00:00:00Z",
            author: GitHubAuthor(login: "dev", name: "Dev")
        )

        // Act
        let metadata = try pr.toPRMetadata()

        // Assert
        #expect(metadata.number == 10)
        #expect(metadata.title == "Feature")
        #expect(metadata.baseRefName == "main")
        #expect(metadata.headRefName == "feature/x")
        #expect(metadata.createdAt == "2025-03-01T00:00:00Z")
        #expect(metadata.author.login == "dev")
        #expect(metadata.author.name == "Dev")
    }

    @Test("new enrichment fields default to nil after toPRMetadata")
    func toPRMetadataEnrichmentFieldsNil() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1,
            title: "PR",
            baseRefName: "main",
            headRefName: "feat",
            createdAt: "2025-01-01T00:00:00Z",
            author: GitHubAuthor(login: "dev")
        )

        // Act
        let metadata = try pr.toPRMetadata()

        // Assert
        #expect(metadata.githubComments == nil)
        #expect(metadata.reviews == nil)
        #expect(metadata.checkRuns == nil)
        #expect(metadata.isMergeable == nil)
    }

    @Test("maps open state to OPEN")
    func toPRMetadataOpenState() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1,
            title: "PR",
            state: "open",
            baseRefName: "main",
            headRefName: "feat",
            createdAt: "2025-01-01T00:00:00Z",
            author: GitHubAuthor(login: "dev")
        )

        // Act
        let metadata = try pr.toPRMetadata()

        // Assert
        #expect(metadata.state == "OPEN")
    }

    @Test("maps draft PR to DRAFT state")
    func toPRMetadataDraftState() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 2,
            title: "Draft PR",
            state: "open",
            isDraft: true,
            baseRefName: "main",
            headRefName: "feat",
            createdAt: "2025-01-01T00:00:00Z",
            author: GitHubAuthor(login: "dev")
        )

        // Act
        let metadata = try pr.toPRMetadata()

        // Assert
        #expect(metadata.state == "DRAFT")
    }

    @Test("maps closed PR with mergedAt to MERGED state")
    func toPRMetadataMergedState() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 3,
            title: "Merged PR",
            state: "closed",
            baseRefName: "main",
            headRefName: "feat",
            createdAt: "2025-01-01T00:00:00Z",
            mergedAt: "2025-02-01T00:00:00Z",
            author: GitHubAuthor(login: "dev")
        )

        // Act
        let metadata = try pr.toPRMetadata()

        // Assert
        #expect(metadata.state == "MERGED")
    }

    @Test("missing baseRefName throws")
    func toPRMetadataThrowsWithoutBaseRefName() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 10,
            title: "Feature",
            headRefName: "feature/x",
            createdAt: "2025-03-01T00:00:00Z",
            author: GitHubAuthor(login: "dev", name: "Dev")
        )

        // Act & Assert
        #expect(throws: PRMetadataConversionError.self) {
            try pr.toPRMetadata()
        }
    }

    @Test("missing author login throws")
    func toPRMetadataThrowsWithoutAuthorLogin() {
        // Arrange
        let pr = GitHubPullRequest(
            number: 10,
            title: "Feature",
            baseRefName: "main",
            headRefName: "feature/x",
            createdAt: "2025-03-01T00:00:00Z"
        )

        // Act & Assert
        #expect(throws: PRMetadataConversionError.self) {
            try pr.toPRMetadata()
        }
    }

    // MARK: - PRMetadata properties

    @Test("id is derived from number")
    func idFromNumber() {
        // Arrange
        let metadata = PRMetadata(
            number: 99,
            title: "Test",
            author: PRMetadata.Author(login: "u", name: "U"),
            state: "OPEN",
            headRefName: "h",
            baseRefName: "main",
            createdAt: "2025-01-01T00:00:00Z"
        )

        // Assert
        #expect(metadata.id == 99)
    }

    @Test("displayNumber formats with hash prefix")
    func displayNumber() {
        // Arrange
        let metadata = PRMetadata(
            number: 123,
            title: "Test",
            author: PRMetadata.Author(login: "u", name: "U"),
            state: "OPEN",
            headRefName: "h",
            baseRefName: "main",
            createdAt: "2025-01-01T00:00:00Z"
        )

        // Assert
        #expect(metadata.displayNumber == "#123")
    }

    @Test("fallback sets empty fields and nil enrichment")
    func fallbackMetadata() {
        // Act
        let metadata = PRMetadata.fallback(number: 5)

        // Assert
        #expect(metadata.number == 5)
        #expect(metadata.baseRefName == "")
        #expect(metadata.headRefName == "")
        #expect(metadata.author.login == "")
        #expect(metadata.githubComments == nil)
        #expect(metadata.reviews == nil)
        #expect(metadata.checkRuns == nil)
        #expect(metadata.isMergeable == nil)
    }

    // MARK: - PRFilter headRefNamePrefix

    @Test("headRefNamePrefix matches PRs with matching prefix")
    func filterMatchesHeadRefNamePrefix() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 1,
            title: "Claude PR",
            baseRefName: "main",
            headRefName: "claude/chain-abc",
            createdAt: "2025-01-01T00:00:00Z",
            author: GitHubAuthor(login: "dev")
        )
        let metadata = try pr.toPRMetadata()
        let filter = PRFilter(headRefNamePrefix: "claude/")

        // Assert
        #expect(filter.matches(metadata))
    }

    @Test("headRefNamePrefix excludes PRs without matching prefix")
    func filterExcludesNonMatchingHeadRefNamePrefix() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 2,
            title: "Feature PR",
            baseRefName: "main",
            headRefName: "feature/x",
            createdAt: "2025-01-01T00:00:00Z",
            author: GitHubAuthor(login: "dev")
        )
        let metadata = try pr.toPRMetadata()
        let filter = PRFilter(headRefNamePrefix: "claude/")

        // Assert
        #expect(!filter.matches(metadata))
    }

    @Test("nil headRefNamePrefix matches all PRs")
    func filterNilHeadRefNamePrefixMatchesAll() throws {
        // Arrange
        let pr = GitHubPullRequest(
            number: 3,
            title: "Any PR",
            baseRefName: "main",
            headRefName: "anything/here",
            createdAt: "2025-01-01T00:00:00Z",
            author: GitHubAuthor(login: "dev")
        )
        let metadata = try pr.toPRMetadata()
        let filter = PRFilter(headRefNamePrefix: nil)

        // Assert
        #expect(filter.matches(metadata))
    }
}
