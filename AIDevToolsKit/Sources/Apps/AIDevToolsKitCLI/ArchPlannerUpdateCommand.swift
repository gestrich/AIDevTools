import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import Foundation

struct ArchPlannerUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Run the next step or a specific step in a planning job"
    )

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Repository path")
    var repoPath: String

    @Option(name: .long, help: "Job ID (UUID)")
    var jobId: String

    @Option(name: .long, help: "Step to run (e.g. form-requirements, compile-arch-info, plan-across-layers)")
    var step: String?

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: jobId) else {
            print("Invalid job ID: \(jobId)")
            return
        }

        let store = try ArchitecturePlannerStore(repoName: repoName)

        let targetStep = step ?? "next"

        switch targetStep {
        case "form-requirements", "next":
            let useCase = FormRequirementsUseCase()
            let options = FormRequirementsUseCase.Options(jobId: uuid, repoPath: repoPath)
            let result = try await useCase.run(options, store: store) { progress in
                switch progress {
                case .extracting: print("Extracting requirements...")
                case .extracted(let count): print("Extracted \(count) requirements")
                case .saved: print("Saved")
                }
            }
            print("Requirements formed: \(result.requirements.count)")

        case "compile-arch-info":
            let useCase = CompileArchitectureInfoUseCase()
            let options = CompileArchitectureInfoUseCase.Options(jobId: uuid, repoPath: repoPath)
            let result = try await useCase.run(options, store: store) { progress in
                switch progress {
                case .loadingGuidelines: print("Loading guidelines...")
                case .identifyingLayers: print("Identifying layers...")
                case .completed: print("Done")
                }
            }
            print("Layers: \(result.layersSummary.prefix(200))")

        case "plan-across-layers":
            let useCase = PlanAcrossLayersUseCase()
            let options = PlanAcrossLayersUseCase.Options(jobId: uuid, repoPath: repoPath)
            let result = try await useCase.run(options, store: store) { progress in
                switch progress {
                case .planning: print("Planning across layers...")
                case .planned(let count): print("Planned \(count) components")
                case .saved: print("Saved")
                }
            }
            print("Components: \(result.componentCount)")

        default:
            print("Unknown step: \(targetStep)")
            print("Available: form-requirements, compile-arch-info, plan-across-layers")
        }
    }
}
