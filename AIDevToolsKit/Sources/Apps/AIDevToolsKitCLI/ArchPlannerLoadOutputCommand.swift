#if canImport(SwiftData)
import AIOutputSDK
import ArchitecturePlannerFeature
import ArgumentParser
import DataPathsService
import Foundation

struct ArchPlannerLoadOutputCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "load-output",
        abstract: "Print the stored AI output for a specific planning step"
    )

    @OptionGroup var dataPathOptions: ArchPlannerCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Job ID (UUID)")
    var jobId: String

    @Option(name: .long, help: "Step index")
    var stepIndex: Int

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: jobId) else {
            print("Invalid job ID: \(jobId)")
            throw ExitCode.failure
        }

        let service = try DataPathsService.fromCLI(dataPath: dataPathOptions.dataPath)
        let workspace = try ArchitecturePlannerWorkspace(dataPathsService: service, repoName: repoName)
        let session = AIRunSession(key: "\(uuid.uuidString)/\(stepIndex)", store: workspace.outputStore)

        guard let output = session.loadOutput() else {
            print("No output found for job \(jobId) step \(stepIndex)")
            throw ExitCode.failure
        }

        print(output)
    }
}
#endif
