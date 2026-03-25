import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import DataPathsService
import Foundation

struct ArchPlannerExecuteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "execute",
        abstract: "Execute the implementation plan"
    )

    @OptionGroup var dataPathOptions: ArchPlannerCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Repository path")
    var repoPath: String

    @Option(name: .long, help: "Job ID (UUID)")
    var jobId: String

    @Flag(name: .long, help: "Use separate AI sessions per phase")
    var separateSessions: Bool = false

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: jobId) else {
            print("Invalid job ID: \(jobId)")
            return
        }

        let store = try DataPathsService.makeArchPlannerStore(dataPath: dataPathOptions.dataPath, repoName: repoName)
        let useCase = ExecuteImplementationUseCase()
        let options = ExecuteImplementationUseCase.Options(
            jobId: uuid,
            repoPath: repoPath,
            reuseSession: !separateSessions
        )

        let result = try await useCase.run(options, store: store) { progress in
            switch progress {
            case .startingPhase(let idx, let summary):
                print("Phase \(idx): \(summary)")
            case .phaseOutput(let text):
                print(text)
            case .phaseCompleted(let idx):
                print("Phase \(idx) completed")
            case .evaluating(let idx):
                print("Evaluating phase \(idx)...")
            case .allCompleted:
                print("All phases completed")
            }
        }

        print("Executed \(result.phasesExecuted) phases, \(result.decisionsRecorded) decisions recorded")
    }
}
