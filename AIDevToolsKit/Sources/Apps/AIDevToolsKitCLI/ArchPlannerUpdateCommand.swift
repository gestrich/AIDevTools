import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import DataPathsService
import Foundation
import SwiftData

struct ArchPlannerUpdateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update",
        abstract: "Run the next step or a specific step in a planning job"
    )

    @OptionGroup var dataPathOptions: ArchPlannerCommand

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Repository path")
    var repoPath: String

    @Option(name: .long, help: "Job ID (UUID)")
    var jobId: String

    @Option(name: .long, help: "Step to run (e.g. form-requirements, compile-arch-info, plan-across-layers, checklist-validation, build-implementation-model, score, execute, report, followups, all, next)")
    var step: String?

    mutating func run() async throws {
        guard let uuid = UUID(uuidString: jobId) else {
            print("Invalid job ID: \(jobId)")
            return
        }

        let store = try DataPathsService.makeArchPlannerStore(dataPath: dataPathOptions.dataPath, repoName: repoName)
        let stepName = step ?? "next"

        if stepName == "all" {
            try await runAllSteps(store: store, jobId: uuid)
        } else {
            let targetStep = try await resolveStep(stepName, store: store, jobId: uuid)
            try await runStep(targetStep, store: store, jobId: uuid)
        }
    }

    private func runAllSteps(store: ArchitecturePlannerStore, jobId: UUID) async throws {
        while true {
            let resolved: String
            do {
                resolved = try await resolveStep("next", store: store, jobId: jobId)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                break
            }
            print("\n--- Running: \(resolved) ---\n")
            try await runStep(resolved, store: store, jobId: jobId)
        }
        print("\nAll steps completed.")
    }

    private func resolveStep(_ stepName: String, store: ArchitecturePlannerStore, jobId: UUID) async throws -> String {
        guard stepName == "next" else { return stepName }

        let currentIndex = try await MainActor.run {
            let context = store.createContext()
            let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
            let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
            guard let job = try context.fetch(descriptor).first else {
                throw ArchitecturePlannerError.jobNotFound(jobId)
            }
            return job.currentStepIndex
        }

        guard let plannerStep = ArchitecturePlannerStep(rawValue: currentIndex) else {
            print("All steps completed (index \(currentIndex))")
            throw ExitCode.success
        }

        let resolved = plannerStep.cliName
        print("Next step: \(plannerStep.name) (\(resolved))")
        return resolved
    }

    private func runStep(_ targetStep: String, store: ArchitecturePlannerStore, jobId: UUID) async throws {
        switch targetStep {
        case "form-requirements":
            let useCase = FormRequirementsUseCase()
            let options = FormRequirementsUseCase.Options(jobId: jobId, repoPath: repoPath)
            let result = try await useCase.run(options, store: store, onProgress: { progress in
                switch progress {
                case .extracting: print("Extracting requirements...")
                case .extracted(let count): print("Extracted \(count) requirements")
                case .saved: print("Saved")
                }
            }, onOutput: { text in
                print(text, terminator: "")
            })
            print("Requirements formed: \(result.requirements.count)")

        case "compile-arch-info":
            let useCase = CompileArchitectureInfoUseCase()
            let options = CompileArchitectureInfoUseCase.Options(jobId: jobId, repoPath: repoPath)
            let result = try await useCase.run(options, store: store, onProgress: { progress in
                switch progress {
                case .loadingGuidelines: print("Loading guidelines...")
                case .identifyingLayers: print("Identifying layers...")
                case .completed: print("Done")
                }
            }, onOutput: { text in
                print(text, terminator: "")
            })
            print("Layers: \(result.layersSummary.prefix(200))")

        case "plan-across-layers":
            let useCase = PlanAcrossLayersUseCase()
            let options = PlanAcrossLayersUseCase.Options(jobId: jobId, repoPath: repoPath)
            let result = try await useCase.run(options, store: store, onProgress: { progress in
                switch progress {
                case .planning: print("Planning across layers...")
                case .planned(let count): print("Planned \(count) components")
                case .saved: print("Saved")
                }
            }, onOutput: { text in
                print(text, terminator: "")
            })
            print("Components: \(result.componentCount)")

        case "checklist-validation":
            let useCase = ChecklistValidationUseCase()
            let options = ChecklistValidationUseCase.Options(jobId: jobId)
            let result = try await MainActor.run {
                try useCase.run(options, store: store) { progress in
                    switch progress {
                    case .validating: print("Validating checklist...")
                    case .validated: print("Validated")
                    }
                }
            }
            print("Requirements covered: \(result.requirementsCovered)/\(result.requirementsTotal)")
            print("Components with mappings: \(result.componentsWithMappings)/\(result.componentsTotal)")

        case "build-implementation-model", "score":
            let useCase = ScoreConformanceUseCase()
            let options = ScoreConformanceUseCase.Options(jobId: jobId, repoPath: repoPath)
            let result = try await useCase.run(options, store: store, onProgress: { progress in
                switch progress {
                case .scoring: print("Scoring conformance...")
                case .scored(let count): print("Created \(count) mappings")
                case .saved: print("Saved")
                }
            }, onOutput: { text in
                print(text, terminator: "")
            })
            print("Average score: \(String(format: "%.1f", result.averageScore))/10")
            print("Mappings: \(result.mappingsCreated)")

        case "review-implementation-plan":
            try await MainActor.run {
                let context = store.createContext()
                let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
                let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
                guard let job = try context.fetch(descriptor).first else {
                    throw ArchitecturePlannerError.jobNotFound(jobId)
                }

                let step = job.processSteps.first { $0.stepIndex == ArchitecturePlannerStep.reviewImplementationPlan.rawValue }
                step?.status = "completed"
                step?.completedAt = Date()
                step?.summary = "Auto-approved (interactive review not yet implemented)"
                job.currentStepIndex = max(job.currentStepIndex, ArchitecturePlannerStep.executeImplementation.rawValue)
                job.updatedAt = Date()
                try context.save()
            }
            print("Review step auto-approved")

        case "execute":
            let useCase = ExecuteImplementationUseCase()
            let options = ExecuteImplementationUseCase.Options(jobId: jobId, repoPath: repoPath)
            let result = try await useCase.run(options, store: store, onProgress: { progress in
                switch progress {
                case .startingPhase(let idx, let summary): print("Phase \(idx): \(summary)")
                case .phaseOutput(let text): print(text)
                case .phaseCompleted(let idx): print("Phase \(idx) completed")
                case .evaluating(let idx): print("Evaluating phase \(idx)...")
                case .allCompleted: print("All phases completed")
                }
            }, onOutput: { text in
                print(text, terminator: "")
            })
            print("Executed \(result.phasesExecuted) phases, \(result.decisionsRecorded) decisions recorded")

        case "report":
            let useCase = GenerateReportUseCase()
            let result = try await MainActor.run {
                try useCase.run(GenerateReportUseCase.Options(jobId: jobId), store: store)
            }
            print(result.report)

        case "followups":
            let useCase = CompileFollowupsUseCase()
            let options = CompileFollowupsUseCase.Options(jobId: jobId, repoPath: repoPath)
            let result = try await useCase.run(options, store: store, onProgress: { progress in
                switch progress {
                case .collecting: print("Collecting followups...")
                case .collected(let count): print("Found \(count) followup items from unclear flags")
                case .identifyingDeferredWork: print("Identifying additional deferred work...")
                case .identified(let count): print("Found \(count) additional followup items")
                case .saved: print("Saved")
                }
            }, onOutput: { text in
                print(text, terminator: "")
            })
            print("Followups created: \(result.followupsCreated)")

        default:
            let allSteps = ArchitecturePlannerStep.allCases.map { $0.cliName }.joined(separator: ", ")
            print("Unknown step: \(targetStep)")
            print("Available: \(allSteps), next")
        }
    }
}
