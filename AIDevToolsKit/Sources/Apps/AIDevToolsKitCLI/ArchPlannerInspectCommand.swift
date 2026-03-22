import ArchitecturePlannerFeature
import ArchitecturePlannerService
import ArgumentParser
import Foundation

struct ArchPlannerInspectCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Inspect a planning job's current state"
    )

    @Option(name: .long, help: "Repository name")
    var repoName: String

    @Option(name: .long, help: "Job ID (UUID). If omitted, lists all jobs.")
    var jobId: String?

    mutating func run() async throws {
        let store = try ArchitecturePlannerStore(repoName: repoName)
        let useCase = ManageGuidelinesUseCase()

        if let jobIdStr = jobId, let uuid = UUID(uuidString: jobIdStr) {
            guard let job = try await MainActor.run(body: { try useCase.getJob(jobId: uuid, store: store) }) else {
                print("Job not found: \(jobIdStr)")
                return
            }
            await MainActor.run { printJob(job) }
        } else {
            let jobs = try await MainActor.run { try useCase.listJobs(repoName: repoName, store: store) }
            if jobs.isEmpty {
                print("No planning jobs found for \(repoName)")
            } else {
                for job in jobs {
                    await MainActor.run { printJobSummary(job) }
                }
            }
        }
    }

    @MainActor
    private func printJob(_ job: PlanningJob) {
        print("Job: \(job.jobId)")
        print("Repo: \(job.repoName) (\(job.repoPath))")
        print("Created: \(job.createdAt.formatted())")
        print("Updated: \(job.updatedAt.formatted())")
        if let request = job.request {
            print("Request: \(request.text)")
        }
        print("\nProcess Steps:")
        for step in job.processSteps.sorted(by: { $0.stepIndex < $1.stepIndex }) {
            let icon: String
            switch step.status {
            case "completed": icon = "✅"
            case "active": icon = "🔄"
            case "stale": icon = "⚠️"
            default: icon = "⏳"
            }
            print("  \(icon) \(step.name): \(step.summary)")
        }
        let reqCount = job.requirements.count
        let compCount = job.implementationComponents.count
        print("\nRequirements: \(reqCount)")
        print("Components: \(compCount)")
        print("Followups: \(job.followupItems.count)")
    }

    @MainActor
    private func printJobSummary(_ job: PlanningJob) {
        let currentStep = job.processSteps
            .sorted(by: { $0.stepIndex < $1.stepIndex })
            .first { $0.status != "completed" }?.name ?? "Complete"
        print("\(job.jobId)  \(job.repoName)  \(currentStep)  \(job.createdAt.formatted())")
    }
}
