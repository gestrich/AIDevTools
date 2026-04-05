import Foundation
import Testing
@testable import ClaudeChainService

@Suite("Project initialization")
struct TestProjectInitialization {

    @Test("creates project with default base path")
    func createProjectWithDefaultBasePath() {
        let project = Project(name: "my-project")

        #expect(project.name == "my-project")
        #expect(project.basePath == "claude-chain/my-project")
    }

    @Test("creates project with custom base path")
    func createProjectWithCustomBasePath() {
        let project = Project(name: "my-project", basePath: "custom/path/my-project")

        #expect(project.name == "my-project")
        #expect(project.basePath == "custom/path/my-project")
    }
}

@Suite("Project path properties")
struct TestProjectPathProperties {

    @Test("configPath returns correct path")
    func configPathProperty() {
        let project = Project(name: "my-project")

        let configPath = project.configPath

        #expect(configPath == "claude-chain/my-project/configuration.yml")
    }

    @Test("specPath returns correct path")
    func specPathProperty() {
        let project = Project(name: "my-project")

        let specPath = project.specPath

        #expect(specPath == "claude-chain/my-project/spec.md")
    }

    @Test("prTemplatePath returns correct path")
    func prTemplatePathProperty() {
        let project = Project(name: "my-project")

        let prTemplatePath = project.prTemplatePath

        #expect(prTemplatePath == "claude-chain/my-project/pr-template.md")
    }

    @Test("metadataFilePath returns correct path")
    func metadataFilePathProperty() {
        let project = Project(name: "my-project")

        let metadataPath = project.metadataFilePath

        #expect(metadataPath == "my-project.json")
    }

    @Test("paths use custom base path")
    func pathsWithCustomBasePath() {
        let project = Project(name: "my-project", basePath: "custom/path/my-project")

        #expect(project.configPath == "custom/path/my-project/configuration.yml")
        #expect(project.specPath == "custom/path/my-project/spec.md")
        #expect(project.prTemplatePath == "custom/path/my-project/pr-template.md")
        #expect(project.metadataFilePath == "my-project.json")
    }

    @Test("reviewPath returns correct path")
    func reviewPathProperty() {
        let project = Project(name: "my-project")

        let reviewPath = project.reviewPath

        #expect(reviewPath == "claude-chain/my-project/review.md")
    }
}

@Suite("Project.fromConfigPath")
struct TestProjectFromConfigPath {

    @Test("extracts project name from standard config path")
    func fromConfigPathStandardFormat() {
        let project = Project.fromConfigPath("claude-chain/my-project/configuration.yml")

        #expect(project.name == "my-project")
        #expect(project.basePath == "claude-chain/my-project")
    }

    @Test("extracts project name from different base directory")
    func fromConfigPathWithDifferentBaseDir() {
        let project = Project.fromConfigPath("custom/my-project/configuration.yml")

        #expect(project.name == "my-project")
        #expect(project.basePath == "custom/my-project")
    }

    @Test("extracts project name from deeply nested path")
    func fromConfigPathWithNestedDirectories() {
        let project = Project.fromConfigPath("deeply/nested/my-project/configuration.yml")

        #expect(project.name == "my-project")
    }
}

@Suite("Project.fromBranchName")
struct TestProjectFromBranchName {

    @Test("extracts project from valid hash-based branch name")
    func fromBranchNameValidHashBasedBranch() throws {
        let result = Project.fromBranchName("claude-chain-my-project-a1b2c3d4")

        let project = try #require(result)
        #expect(project.name == "my-project")
        #expect(project.basePath == "claude-chain/my-project")
    }

    @Test("extracts hyphenated project name from branch")
    func fromBranchNameWithHyphenatedProjectName() throws {
        let result = Project.fromBranchName("claude-chain-my-complex-project-name-12345678")

        let project = try #require(result)
        #expect(project.name == "my-complex-project-name")
    }

    @Test("returns nil for invalid branch name formats")
    func fromBranchNameInvalidFormatReturnsNil() {
        let invalidBranches = [
            "invalid-branch-name",
            "claude-chain-project",
            "claude-chain-abc",
            "main",
            "feature/something",
            "claude-chain-project-5",
            "claude-chain-project-123",
            "claude-chain-project-abcdefg",
            "claude-chain-project-abcdefghi",
            "claude-chain-project-ABCDEF12",
            "claude-chain-project-xyz12345",
        ]

        for branchName in invalidBranches {
            #expect(Project.fromBranchName(branchName) == nil, "Should return nil for: \(branchName)")
        }
    }

    @Test("extracts project from branches with various valid hex hashes")
    func fromBranchNameVariousHexHashes() {
        let testCases = [
            ("claude-chain-my-project-00000000", "my-project"),
            ("claude-chain-my-project-ffffffff", "my-project"),
            ("claude-chain-my-project-12abcdef", "my-project"),
            ("claude-chain-other-proj-a1b2c3d4", "other-proj"),
        ]

        for (branchName, expectedName) in testCases {
            let project = Project.fromBranchName(branchName)
            #expect(project != nil, "Should parse: \(branchName)")
            #expect(project?.name == expectedName)
        }
    }
}

@Suite("Project.findAll")
struct TestProjectFindAll {

    @Test("discovers multiple projects in directory")
    func findAllDiscoversMultipleProjects() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        for projectName in ["project-a", "project-b", "project-c"] {
            let projectDir = baseDir.appendingPathComponent(projectName)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        }

        let projects = Project.findAll(baseDir: baseDir.path)

        #expect(projects.count == 3)
        let names = projects.map(\.name)
        #expect(names.contains("project-a"))
        #expect(names.contains("project-b"))
        #expect(names.contains("project-c"))
    }

    @Test("returns projects sorted by name")
    func findAllReturnsSortedProjects() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        for projectName in ["zebra", "alpha", "middle"] {
            let projectDir = baseDir.appendingPathComponent(projectName)
            try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
            try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        }

        let projects = Project.findAll(baseDir: baseDir.path)

        #expect(projects.count == 3)
        #expect(projects.map(\.name) == ["alpha", "middle", "zebra"])
    }

    @Test("ignores directories without spec.md")
    func findAllIgnoresDirectoriesWithoutSpec() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let validProject = baseDir.appendingPathComponent("valid-project")
        try FileManager.default.createDirectory(at: validProject, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: validProject.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: baseDir.appendingPathComponent("invalid-project-1"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: baseDir.appendingPathComponent("invalid-project-2"), withIntermediateDirectories: true)

        let projects = Project.findAll(baseDir: baseDir.path)

        #expect(projects.count == 1)
        #expect(projects[0].name == "valid-project")
    }

    @Test("discovers projects with spec.md but no configuration.yml")
    func findAllDiscoversProjectsWithoutConfig() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let specOnly = baseDir.appendingPathComponent("spec-only-project")
        try FileManager.default.createDirectory(at: specOnly, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: specOnly.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)

        let full = baseDir.appendingPathComponent("full-project")
        try FileManager.default.createDirectory(at: full, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: full.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        try "reviewers: []".write(to: full.appendingPathComponent("configuration.yml"), atomically: true, encoding: .utf8)

        let projects = Project.findAll(baseDir: baseDir.path)

        #expect(projects.count == 2)
        let names = projects.map(\.name)
        #expect(names.contains("spec-only-project"))
        #expect(names.contains("full-project"))
    }

    @Test("ignores directories with only configuration.yml")
    func findAllIgnoresDirectoriesWithOnlyConfig() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let configOnly = baseDir.appendingPathComponent("config-only")
        try FileManager.default.createDirectory(at: configOnly, withIntermediateDirectories: true)
        try "reviewers: []".write(to: configOnly.appendingPathComponent("configuration.yml"), atomically: true, encoding: .utf8)

        let valid = baseDir.appendingPathComponent("valid-project")
        try FileManager.default.createDirectory(at: valid, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: valid.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)

        let projects = Project.findAll(baseDir: baseDir.path)

        #expect(projects.count == 1)
        #expect(projects[0].name == "valid-project")
    }

    @Test("ignores files in base directory")
    func findAllIgnoresFilesInBaseDir() throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-chain-\(UUID())")
        try FileManager.default.createDirectory(at: baseDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let projectDir = baseDir.appendingPathComponent("my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)
        try "# Readme".write(to: baseDir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "content".write(to: baseDir.appendingPathComponent("some-file.txt"), atomically: true, encoding: .utf8)

        let projects = Project.findAll(baseDir: baseDir.path)

        #expect(projects.count == 1)
        #expect(projects[0].name == "my-project")
    }

    @Test("returns empty list when directory does not exist")
    func findAllReturnsEmptyListWhenDirectoryNotExists() {
        let nonExistentDir = FileManager.default.temporaryDirectory.appendingPathComponent("non-existent-\(UUID())")

        let projects = Project.findAll(baseDir: nonExistentDir.path)

        #expect(projects == [])
    }

    @Test("discovers projects in custom base directory")
    func findAllWithCustomBaseDir() throws {
        let customDir = FileManager.default.temporaryDirectory.appendingPathComponent("custom-projects-\(UUID())")
        try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: customDir) }

        let projectDir = customDir.appendingPathComponent("my-project")
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try "- [ ] Task 1".write(to: projectDir.appendingPathComponent("spec.md"), atomically: true, encoding: .utf8)

        let projects = Project.findAll(baseDir: customDir.path)

        #expect(projects.count == 1)
        #expect(projects[0].name == "my-project")
    }
}

@Suite("Project equality and hashing")
struct TestProjectEquality {

    @Test("equal when name and basePath match")
    func equalitySameNameAndBasePath() {
        let project1 = Project(name: "my-project")
        let project2 = Project(name: "my-project")

        #expect(project1 == project2)
    }

    @Test("not equal when names differ")
    func equalityDifferentNames() {
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")

        #expect(project1 != project2)
    }

    @Test("not equal when base paths differ")
    func equalityDifferentBasePaths() {
        let project1 = Project(name: "my-project", basePath: "claude-chain/my-project")
        let project2 = Project(name: "my-project", basePath: "custom/my-project")

        #expect(project1 != project2)
    }

    @Test("equal projects have the same hash")
    func hashSameForEqualProjects() {
        let project1 = Project(name: "my-project")
        let project2 = Project(name: "my-project")

        #expect(project1.hashValue == project2.hashValue)
    }

    @Test("different projects have different hashes")
    func hashDifferentForDifferentProjects() {
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")

        #expect(project1.hashValue != project2.hashValue)
    }

    @Test("usable in Set — deduplicates equal projects")
    func canUseInSet() {
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")
        let project3 = Project(name: "project-a")

        let projectSet: Set<Project> = [project1, project2, project3]

        #expect(projectSet.count == 2)
        #expect(projectSet.contains(project1))
        #expect(projectSet.contains(project2))
    }

    @Test("usable as dictionary key")
    func canUseAsDictKey() {
        let project1 = Project(name: "project-a")
        let project2 = Project(name: "project-b")

        let dict = [project1: "data-a", project2: "data-b"]

        #expect(dict[project1] == "data-a")
        #expect(dict[project2] == "data-b")
    }
}

@Suite("Project description")
struct TestProjectDescription {

    @Test("description contains name and base path")
    func descriptionContainsNameAndBasePath() {
        let project = Project(name: "my-project")

        let description = project.description

        #expect(description.contains("Project"))
        #expect(description.contains("my-project"))
        #expect(description.contains("claude-chain/my-project"))
    }

    @Test("description includes custom base path")
    func descriptionWithCustomBasePath() {
        let project = Project(name: "my-project", basePath: "custom/path")

        let description = project.description

        #expect(description.contains("my-project"))
        #expect(description.contains("custom/path"))
    }
}
