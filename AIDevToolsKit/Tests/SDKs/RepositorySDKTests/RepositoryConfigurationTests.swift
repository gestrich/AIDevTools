import Foundation
import Testing
@testable import RepositorySDK

struct RepositoryConfigurationTests {
    @Test func initDefaultsNameToLastPathComponent() {
        // Arrange & Act
        let repo = RepositoryConfiguration(path: URL(filePath: "/Users/test/my-project"))

        // Assert
        #expect(repo.name == "my-project")
    }

    @Test func initUsesExplicitName() {
        // Arrange & Act
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"), name: "Custom Name")

        // Assert
        #expect(repo.name == "Custom Name")
    }

    @Test func codableRoundTrip() throws {
        // Arrange
        let repo = RepositoryConfiguration(
            path: URL(filePath: "/Users/test/my-repo"),
            name: "my-repo",
            credentialAccount: "gestrich",
            description: "A test repository",
            recentFocus: "Adding auth",
            skills: ["swift", "swiftui"],
            architectureDocs: ["docs/arch.md"],
            verification: Verification(commands: ["swift build", "swift test"], notes: "macOS only"),
            pullRequest: PullRequestConfig(
                baseBranch: "main",
                branchNamingConvention: "feature/<name>",
                template: "## Summary\n",
                notes: "Require 2 approvals"
            )
        )

        // Act
        let data = try JSONEncoder().encode(repo)
        let decoded = try JSONDecoder().decode(RepositoryConfiguration.self, from: data)

        // Assert
        #expect(decoded.id == repo.id)
        #expect(decoded.path == repo.path)
        #expect(decoded.name == "my-repo")
        #expect(decoded.credentialAccount == "gestrich")
        #expect(decoded.description == "A test repository")
        #expect(decoded.recentFocus == "Adding auth")
        #expect(decoded.skills == ["swift", "swiftui"])
        #expect(decoded.architectureDocs == ["docs/arch.md"])
        #expect(decoded.verification == Verification(commands: ["swift build", "swift test"], notes: "macOS only"))
        #expect(decoded.pullRequest == PullRequestConfig(
            baseBranch: "main",
            branchNamingConvention: "feature/<name>",
            template: "## Summary\n",
            notes: "Require 2 approvals"
        ))
    }

    @Test func codableWithMinimalFields() throws {
        // Arrange
        let repo = RepositoryConfiguration(path: URL(filePath: "/tmp/repo"))

        // Act
        let data = try JSONEncoder().encode(repo)
        let decoded = try JSONDecoder().decode(RepositoryConfiguration.self, from: data)

        // Assert
        #expect(decoded.id == repo.id)
        #expect(decoded.path == repo.path)
        #expect(decoded.name == "repo")
        #expect(decoded.credentialAccount == nil)
        #expect(decoded.description == nil)
        #expect(decoded.verification == nil)
        #expect(decoded.pullRequest == nil)
    }
}
