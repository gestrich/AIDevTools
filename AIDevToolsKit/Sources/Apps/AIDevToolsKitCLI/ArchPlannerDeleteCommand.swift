import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import DataPathsService
import Foundation

struct ArchPlannerDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete a planning job"
    )

    @OptionGroup var dataPathOptions: ArchPlannerCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Argument(help: "Job ID (UUID) to delete")
    var jobId: String

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: jobId) else {
            print("Invalid UUID: \(jobId)")
            throw ExitCode.failure
        }

        let store = try DataPathsService.makeArchPlannerStore(dataPath: dataPathOptions.dataPath, repoName: repoName)
        let useCase = ManageGuidelinesUseCase()

        guard try await MainActor.run(body: { try useCase.getJob(jobId: uuid, store: store) }) != nil else {
            print("Job not found: \(jobId)")
            throw ExitCode.failure
        }

        try await MainActor.run { try useCase.deleteJob(jobId: uuid, store: store) }
        printColored("Deleted job \(jobId)", color: .green)
    }
}
