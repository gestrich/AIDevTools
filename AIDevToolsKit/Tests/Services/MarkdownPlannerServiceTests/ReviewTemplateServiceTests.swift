import Foundation
import Testing
@testable import MarkdownPlannerService

struct ReviewTemplateServiceTests {
    private func makeTempDirectory() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        return tempDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func writeFile(named name: String, contents: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func availableTemplatesReturnsSortedAlphabetically() throws {
        // Arrange
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }
        try writeFile(named: "zebra-check.md", contents: "## - [ ] Step Z", in: tempDir)
        try writeFile(named: "alpha-check.md", contents: "## - [ ] Step A", in: tempDir)
        try writeFile(named: "middle-check.md", contents: "## - [ ] Step M", in: tempDir)
        let service = ReviewTemplateService(reviewsDirectory: tempDir)

        // Act
        let templates = try service.availableTemplates()

        // Assert
        #expect(templates.map(\.id) == ["alpha-check", "middle-check", "zebra-check"])
    }

    @Test func availableTemplatesSkipsNonMarkdownFiles() throws {
        // Arrange
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }
        try writeFile(named: "valid.md", contents: "## - [ ] Step", in: tempDir)
        try writeFile(named: "ignored.txt", contents: "not markdown", in: tempDir)
        try writeFile(named: "also-ignored", contents: "no extension", in: tempDir)
        let service = ReviewTemplateService(reviewsDirectory: tempDir)

        // Act
        let templates = try service.availableTemplates()

        // Assert
        #expect(templates.count == 1)
        #expect(templates[0].id == "valid")
    }

    @Test func availableTemplatesConvertsHyphensToSpacesInName() throws {
        // Arrange
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }
        try writeFile(named: "architecture-compliance.md", contents: "## - [ ] Step", in: tempDir)
        let service = ReviewTemplateService(reviewsDirectory: tempDir)

        // Act
        let templates = try service.availableTemplates()

        // Assert
        #expect(templates[0].name == "architecture compliance")
    }

    @Test func loadStepsParsesUncheckedLines() throws {
        // Arrange
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }
        let url = try writeFile(named: "review.md", contents: """
            ## - [ ] First step description
            ## - [ ] Second step description
            """, in: tempDir)
        let template = ReviewTemplate(id: "review", name: "review", url: url)
        let service = ReviewTemplateService(reviewsDirectory: tempDir)

        // Act
        let steps = try service.loadSteps(from: template)

        // Assert
        #expect(steps == ["First step description", "Second step description"])
    }

    @Test func loadStepsIncludesCompletedLines() throws {
        // Arrange
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }
        let url = try writeFile(named: "review.md", contents: """
            ## - [x] Already done step
            ## - [ ] Pending step
            """, in: tempDir)
        let template = ReviewTemplate(id: "review", name: "review", url: url)
        let service = ReviewTemplateService(reviewsDirectory: tempDir)

        // Act
        let steps = try service.loadSteps(from: template)

        // Assert
        #expect(steps == ["Already done step", "Pending step"])
    }

    @Test func loadStepsSkipsNonHeadingLines() throws {
        // Arrange
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }
        let url = try writeFile(named: "review.md", contents: """
            # Title line
            Some body text here.

            **Bold text**
            ## - [ ] Valid step
            - bullet point
            """, in: tempDir)
        let template = ReviewTemplate(id: "review", name: "review", url: url)
        let service = ReviewTemplateService(reviewsDirectory: tempDir)

        // Act
        let steps = try service.loadSteps(from: template)

        // Assert
        #expect(steps == ["Valid step"])
    }

    @Test func loadStepsReturnsEmptyForFileWithNoSteps() throws {
        // Arrange
        let tempDir = try makeTempDirectory()
        defer { cleanup(tempDir) }
        let url = try writeFile(named: "review.md", contents: """
            # Just a title

            Some content without any checklist items.
            """, in: tempDir)
        let template = ReviewTemplate(id: "review", name: "review", url: url)
        let service = ReviewTemplateService(reviewsDirectory: tempDir)

        // Act
        let steps = try service.loadSteps(from: template)

        // Assert
        #expect(steps.isEmpty)
    }
}
