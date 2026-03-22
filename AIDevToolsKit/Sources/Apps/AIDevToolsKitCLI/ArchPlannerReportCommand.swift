import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import Foundation

struct ArchPlannerReportCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "report",
        abstract: "Generate a final report for a planning job"
    )

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Job ID (UUID)")
    var jobId: String

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: jobId) else {
            print("Invalid job ID: \(jobId)")
            return
        }

        let store = try ArchitecturePlannerStore(repoName: repoName)
        let useCase = GenerateReportUseCase()
        let result = try await MainActor.run {
            try useCase.run(GenerateReportUseCase.Options(jobId: uuid), store: store)
        }
        print(result.report)
    }
}
