import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import Foundation

struct ArchPlannerScoreCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "score",
        abstract: "Score implementation components against guidelines"
    )

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Repository path")
    var repoPath: String

    @Option(name: .long, help: "Job ID (UUID)")
    var jobId: String

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: jobId) else {
            print("Invalid job ID: \(jobId)")
            return
        }

        let store = try ArchitecturePlannerStore(repoName: repoName)
        let useCase = ScoreConformanceUseCase()
        let options = ScoreConformanceUseCase.Options(jobId: uuid, repoPath: repoPath)

        let result = try await useCase.run(options, store: store) { progress in
            switch progress {
            case .scoring: print("Scoring conformance...")
            case .scored(let count): print("Created \(count) mappings")
            case .saved: print("Saved")
            }
        }

        print("Average score: \(String(format: "%.1f", result.averageScore))/10")
        print("Mappings: \(result.mappingsCreated)")
    }
}
