import ArchitecturePlannerService
import Foundation
import SwiftData

/// CRUD operations for guidelines and categories.
public struct ManageGuidelinesUseCase: Sendable {

    public init() {}

    // MARK: - List Guidelines

    @MainActor
    public func listGuidelines(repoName: String, store: ArchitecturePlannerStore) throws -> [Guideline] {
        let context = store.createContext()
        let predicate = #Predicate<Guideline> { $0.repoName == repoName }
        let descriptor = FetchDescriptor<Guideline>(predicate: predicate, sortBy: [SortDescriptor(\.title)])
        return try context.fetch(descriptor)
    }

    // MARK: - List Categories

    @MainActor
    public func listCategories(repoName: String, store: ArchitecturePlannerStore) throws -> [GuidelineCategory] {
        let context = store.createContext()
        let predicate = #Predicate<GuidelineCategory> { $0.repoName == repoName }
        let descriptor = FetchDescriptor<GuidelineCategory>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        return try context.fetch(descriptor)
    }

    // MARK: - Create Guideline

    public struct CreateGuidelineOptions: Sendable {
        public let repoName: String
        public let title: String
        public let body: String
        public let filePathGlobs: [String]
        public let descriptionMatchers: [String]
        public let goodExamples: [String]
        public let badExamples: [String]
        public let highLevelOverview: String
        public let categoryNames: [String]

        public init(
            repoName: String,
            title: String,
            body: String = "",
            filePathGlobs: [String] = [],
            descriptionMatchers: [String] = [],
            goodExamples: [String] = [],
            badExamples: [String] = [],
            highLevelOverview: String = "",
            categoryNames: [String] = []
        ) {
            self.repoName = repoName
            self.title = title
            self.body = body
            self.filePathGlobs = filePathGlobs
            self.descriptionMatchers = descriptionMatchers
            self.goodExamples = goodExamples
            self.badExamples = badExamples
            self.highLevelOverview = highLevelOverview
            self.categoryNames = categoryNames
        }
    }

    @MainActor
    public func createGuideline(_ options: CreateGuidelineOptions, store: ArchitecturePlannerStore) throws -> Guideline {
        let context = store.createContext()

        let guideline = Guideline(
            repoName: options.repoName,
            title: options.title,
            body: options.body,
            filePathGlobs: options.filePathGlobs,
            descriptionMatchers: options.descriptionMatchers,
            goodExamples: options.goodExamples,
            badExamples: options.badExamples,
            highLevelOverview: options.highLevelOverview
        )

        // Link categories
        let repoNameForPredicate = options.repoName
        let allCatsPredicate = #Predicate<GuidelineCategory> { $0.repoName == repoNameForPredicate }
        let allCatsDescriptor = FetchDescriptor<GuidelineCategory>(predicate: allCatsPredicate)
        let existingCategories = try context.fetch(allCatsDescriptor)

        for catName in options.categoryNames {
            if let existingCat = existingCategories.first(where: { $0.name == catName }) {
                guideline.categories.append(existingCat)
            } else {
                let newCat = GuidelineCategory(name: catName, repoName: options.repoName)
                context.insert(newCat)
                guideline.categories.append(newCat)
            }
        }

        context.insert(guideline)
        try context.save()
        return guideline
    }

    // MARK: - Delete Guideline

    @MainActor
    public func deleteGuideline(guidelineId: UUID, store: ArchitecturePlannerStore) throws {
        let context = store.createContext()
        let predicate = #Predicate<Guideline> { $0.guidelineId == guidelineId }
        let descriptor = FetchDescriptor<Guideline>(predicate: predicate)
        guard let guideline = try context.fetch(descriptor).first else { return }
        context.delete(guideline)
        try context.save()
    }

    // MARK: - Load Planning Jobs

    @MainActor
    public func listJobs(repoName: String, store: ArchitecturePlannerStore) throws -> [PlanningJob] {
        let context = store.createContext()
        let predicate = #Predicate<PlanningJob> { $0.repoName == repoName }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate, sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return try context.fetch(descriptor)
    }

    // MARK: - Get Job

    @MainActor
    public func getJob(jobId: UUID, store: ArchitecturePlannerStore) throws -> PlanningJob? {
        let context = store.createContext()
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        return try context.fetch(descriptor).first
    }

    // MARK: - Mark Steps Stale

    /// When a user reruns a prior step, mark all subsequent steps as stale.
    @MainActor
    public func markSubsequentStepsStale(jobId: UUID, fromStepIndex: Int, store: ArchitecturePlannerStore) throws {
        let context = store.createContext()
        let predicate = #Predicate<PlanningJob> { $0.jobId == jobId }
        let descriptor = FetchDescriptor<PlanningJob>(predicate: predicate)
        guard let job = try context.fetch(descriptor).first else { return }

        for step in job.processSteps where step.stepIndex > fromStepIndex {
            if step.status == "completed" {
                step.status = "stale"
            }
        }
        job.currentStepIndex = fromStepIndex
        job.updatedAt = Date()
        try context.save()
    }
}
