import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import Foundation

struct ArchPlannerGuidelinesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "guidelines",
        abstract: "Manage architectural guidelines",
        subcommands: [GuidelinesListCommand.self, GuidelinesAddCommand.self, GuidelinesDeleteCommand.self]
    )
}

struct GuidelinesListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List guidelines for a repository"
    )

    @Option(name: .long, help: "Repository name")
    var repoName: String

    mutating func run() async throws {
        let store = try ArchitecturePlannerStore(repoName: repoName)
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
        let store = try ArchitecturePlannerStore(repoName: repoName)
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

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Guideline ID (UUID)")
    var guidelineId: String

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: guidelineId) else {
            print("Invalid guideline ID: \(guidelineId)")
            return
        }

        let store = try ArchitecturePlannerStore(repoName: repoName)
        let useCase = ManageGuidelinesUseCase()
        try await MainActor.run { try useCase.deleteGuideline(guidelineId: uuid, store: store) }
        print("Deleted guideline: \(guidelineId)")
    }
}
