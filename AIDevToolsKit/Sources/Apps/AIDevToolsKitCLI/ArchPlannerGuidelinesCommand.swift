import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import DataPathsService
import Foundation

struct ArchPlannerGuidelinesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guidelines",
        abstract: "Manage architectural guidelines",
        subcommands: [GuidelinesAddCommand.self, GuidelinesDeleteCommand.self, GuidelinesListCommand.self, GuidelinesSeedCommand.self]
    )

    @OptionGroup var dataPathOptions: ArchPlannerCommand
}

struct GuidelinesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List guidelines for a repository"
    )

    @OptionGroup var dataPathOptions: ArchPlannerGuidelinesCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    mutating func run() async throws {
        let store = try DataPathsService.makeArchPlannerStore(dataPath: dataPathOptions.dataPathOptions.dataPath, repoName: repoName)
        let useCase = ManageGuidelinesUseCase()
        let guidelines = try await MainActor.run { try useCase.listGuidelines(repoName: repoName, store: store) }

        if guidelines.isEmpty {
            print("No guidelines found for \(repoName)")
        } else {
            for g in guidelines {
                let cats = g.categories.map { $0.name }.joined(separator: ", ")
                print("\(g.guidelineId)  \(g.title)  [\(cats)]")
            }
        }
    }
}

struct GuidelinesAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a guideline"
    )

    @OptionGroup var dataPathOptions: ArchPlannerGuidelinesCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Guideline title")
    var title: String

    @Option(name: .long, help: "Guideline body")
    var body: String = ""

    @Option(name: .long, help: "High-level overview")
    var overview: String = ""

    @Option(name: .long, help: "Categories (comma-separated)")
    var categories: String = ""

    @Option(name: .long, help: "File path globs (comma-separated)")
    var fileGlobs: String = ""

    mutating func run() async throws {
        let store = try DataPathsService.makeArchPlannerStore(dataPath: dataPathOptions.dataPathOptions.dataPath, repoName: repoName)
        let useCase = ManageGuidelinesUseCase()

        let catNames = categories.isEmpty ? [] : categories.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
        let globs = fileGlobs.isEmpty ? [] : fileGlobs.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }

        let guideline = try await MainActor.run {
            try useCase.createGuideline(
                ManageGuidelinesUseCase.CreateGuidelineOptions(
                    repoName: repoName,
                    title: title,
                    body: body,
                    filePathGlobs: globs,
                    highLevelOverview: overview,
                    categoryNames: catNames
                ),
                store: store
            )
        }
        print("Created guideline: \(guideline.guidelineId) — \(guideline.title)")
    }
}

struct GuidelinesDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a guideline"
    )

    @OptionGroup var dataPathOptions: ArchPlannerGuidelinesCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Guideline ID (UUID)")
    var guidelineId: String

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: guidelineId) else {
            print("Invalid guideline ID: \(guidelineId)")
            return
        }

        let store = try DataPathsService.makeArchPlannerStore(dataPath: dataPathOptions.dataPathOptions.dataPath, repoName: repoName)
        let useCase = ManageGuidelinesUseCase()
        try await MainActor.run { try useCase.deleteGuideline(guidelineId: uuid, store: store) }
        print("Deleted guideline: \(guidelineId)")
    }
}

struct GuidelinesSeedCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "seed",
        abstract: "Seed guidelines from bundled skills and ARCHITECTURE.md"
    )

    @OptionGroup var dataPathOptions: ArchPlannerGuidelinesCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Repository path")
    var repoPath: String

    mutating func run() async throws {
        let store = try DataPathsService.makeArchPlannerStore(dataPath: dataPathOptions.dataPathOptions.dataPath, repoName: repoName)
        let useCase = SeedGuidelinesUseCase()
        let result = try await MainActor.run {
            try useCase.run(
                SeedGuidelinesUseCase.Options(repoName: repoName, repoPath: repoPath),
                store: store
            )
        }

        if result.skipped {
            print("Guidelines already exist for \(repoName) — skipped seeding")
        } else {
            print("Seeded \(result.guidelinesCreated) guidelines for \(repoName)")
        }
    }
}
