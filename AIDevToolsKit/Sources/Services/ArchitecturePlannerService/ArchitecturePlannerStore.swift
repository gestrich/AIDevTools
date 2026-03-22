import Foundation
import SwiftData

/// Provides SwiftData persistence for architecture planning models.
/// Store is per-repo at ~/.ai-dev-tools/{repo-name}/architecture-planner/
public final class ArchitecturePlannerStore: Sendable {

    private let modelContainer: ModelContainer

    public var container: ModelContainer { modelContainer }

    public init(repoName: String) throws {
        let basePath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ai-dev-tools")
            .appendingPathComponent(repoName)
            .appendingPathComponent("architecture-planner")

        try FileManager.default.createDirectory(at: basePath, withIntermediateDirectories: true)

        let storeURL = basePath.appendingPathComponent("store.sqlite")

        let schema = Schema([
            ArchitectureRequest.self,
            FollowupItem.self,
            Guideline.self,
            GuidelineCategory.self,
            GuidelineMapping.self,
            ImplementationComponent.self,
            PhaseDecision.self,
            PlanningJob.self,
            ProcessStep.self,
            Requirement.self,
            UnclearFlag.self,
        ])

        let config = ModelConfiguration(
            "ArchitecturePlanner",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )

        self.modelContainer = try ModelContainer(for: schema, configurations: [config])
    }

    @MainActor
    public func createContext() -> ModelContext {
        ModelContext(modelContainer)
    }
}
