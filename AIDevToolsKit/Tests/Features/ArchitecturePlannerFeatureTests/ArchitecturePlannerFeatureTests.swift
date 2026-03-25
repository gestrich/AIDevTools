import Foundation
import SwiftData
import Testing
@testable import ArchitecturePlannerFeature
@testable import ArchitecturePlannerService

@Suite
struct CreatePlanningJobUseCaseTests {

    @Test @MainActor func createJob() throws {
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent("test-create-\(UUID().uuidString.prefix(8))")
        let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
        let useCase = CreatePlanningJobUseCase()

        let options = CreatePlanningJobUseCase.Options(
            repoName: "TestRepo",
            repoPath: "/tmp/test",
            featureDescription: "Build a cool feature"
        )

        let result = try useCase.run(options, store: store)
        #expect(result.jobId != UUID())

        // Verify persisted
        let context = store.createContext()
        let jobId = result.jobId
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        let jobs = try context.fetch(descriptor)
        #expect(jobs.count == 1)

        let job = jobs[0]
        #expect(job.repoName == "TestRepo")
        #expect(job.request?.text == "Build a cool feature")
        #expect(job.processSteps.count == ArchitecturePlannerStep.allCases.count)
        #expect(job.currentStepIndex == 1) // past describe feature
    }
}

@Suite
struct ManageGuidelinesUseCaseTests {

    @Test @MainActor func createAndListGuidelines() throws {
        let repoName = "test-guidelines-\(UUID().uuidString.prefix(8))"
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(repoName)
        let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
        let useCase = ManageGuidelinesUseCase()

        // Initially empty
        let initial = try useCase.listGuidelines(repoName: repoName, store: store)
        #expect(initial.isEmpty)

        // Create a guideline
        let options = ManageGuidelinesUseCase.CreateGuidelineOptions(
            repoName: repoName,
            title: "Layer Dependencies",
            body: "Higher layers depend on lower layers only",
            filePathGlobs: ["Sources/**"],
            highLevelOverview: "Enforce unidirectional dependencies",
            categoryNames: ["architecture"]
        )
        let guideline = try useCase.createGuideline(options, store: store)
        #expect(guideline.title == "Layer Dependencies")

        // List should now have one
        let after = try useCase.listGuidelines(repoName: repoName, store: store)
        #expect(after.count == 1)

        // Category created
        let categories = try useCase.listCategories(repoName: repoName, store: store)
        #expect(categories.count == 1)
        #expect(categories[0].name == "architecture")
    }

    @Test @MainActor func deleteGuideline() throws {
        let repoName = "test-delete-\(UUID().uuidString.prefix(8))"
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(repoName)
        let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
        let useCase = ManageGuidelinesUseCase()

        let options = ManageGuidelinesUseCase.CreateGuidelineOptions(
            repoName: repoName,
            title: "Test Guideline"
        )
        let guideline = try useCase.createGuideline(options, store: store)

        try useCase.deleteGuideline(guidelineId: guideline.guidelineId, store: store)
        let after = try useCase.listGuidelines(repoName: repoName, store: store)
        #expect(after.isEmpty)
    }

    @Test @MainActor func listJobsAndGetJob() throws {
        let repoName = "test-jobs-\(UUID().uuidString.prefix(8))"
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(repoName)
        let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
        let createUseCase = CreatePlanningJobUseCase()
        let manageUseCase = ManageGuidelinesUseCase()

        let result = try createUseCase.run(
            CreatePlanningJobUseCase.Options(
                repoName: repoName,
                repoPath: "/tmp/test",
                featureDescription: "Test feature"
            ),
            store: store
        )

        let jobs = try manageUseCase.listJobs(repoName: repoName, store: store)
        #expect(jobs.count == 1)

        let job = try manageUseCase.getJob(jobId: result.jobId, store: store)
        #expect(job != nil)
        #expect(job?.repoName == repoName)
    }

    @Test @MainActor func markStepsStale() throws {
        let repoName = "test-stale-\(UUID().uuidString.prefix(8))"
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(repoName)
        let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
        let createUseCase = CreatePlanningJobUseCase()
        let manageUseCase = ManageGuidelinesUseCase()

        let result = try createUseCase.run(
            CreatePlanningJobUseCase.Options(
                repoName: repoName,
                repoPath: "/tmp/test",
                featureDescription: "Test feature"
            ),
            store: store
        )

        // Manually mark some steps as completed using the same approach as the use case
        let context = store.createContext()
        let jobId = result.jobId
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        let job = try context.fetch(descriptor).first!
        for step in job.processSteps where step.stepIndex <= 3 {
            step.status = "completed"
        }
        job.currentStepIndex = 4
        try context.save()

        // Mark stale from step 1
        try manageUseCase.markSubsequentStepsStale(jobId: result.jobId, fromStepIndex: 1, store: store)

        let updatedJob = try manageUseCase.getJob(jobId: result.jobId, store: store)!
        let staleSteps = updatedJob.processSteps.filter { $0.status == "stale" }
        #expect(staleSteps.count == 2) // steps 2 and 3
        #expect(updatedJob.currentStepIndex == 1)
    }
}

@Suite
struct GenerateReportUseCaseTests {

    @Test @MainActor func generateReport() throws {
        let repoName = "test-report-\(UUID().uuidString.prefix(8))"
        let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(repoName)
        let store = try ArchitecturePlannerStore(directoryURL: directoryURL)
        let createUseCase = CreatePlanningJobUseCase()
        let reportUseCase = GenerateReportUseCase()

        let result = try createUseCase.run(
            CreatePlanningJobUseCase.Options(
                repoName: repoName,
                repoPath: "/tmp/test",
                featureDescription: "Build something amazing"
            ),
            store: store
        )

        let report = try reportUseCase.run(
            GenerateReportUseCase.Options(jobId: result.jobId),
            store: store
        )

        #expect(report.report.contains("Architecture Planning Report"))
        #expect(report.report.contains(repoName))
        #expect(report.report.contains("Build something amazing"))
    }
}
