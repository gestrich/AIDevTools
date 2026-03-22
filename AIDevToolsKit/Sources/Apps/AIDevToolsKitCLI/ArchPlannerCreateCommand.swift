import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import Foundation

struct ArchPlannerCreateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create",
        abstract: "Create a new architecture planning job"
    )

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Repository path")
    var repoPath: String

    @Argument(help: "Feature description")
    var description: String

    mutating func run() async throws {
        let store = try ArchitecturePlannerStore(repoName: repoName)
        let useCase = CreatePlanningJobUseCase()
        let options = CreatePlanningJobUseCase.Options(
            repoName: repoName,
            repoPath: repoPath,
            featureDescription: description
        )
        let result = try await MainActor.run {
            try useCase.run(options, store: store)
        }
        print("Created planning job: \(result.jobId)")
    }
}
