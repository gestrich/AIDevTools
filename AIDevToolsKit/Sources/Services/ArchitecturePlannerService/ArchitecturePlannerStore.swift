import Foundation
import SwiftData

public final class ArchitecturePlannerStore: Sendable {

    private let modelContainer: ModelContainer

    public var container: ModelContainer { modelContainer }

    public init(directoryURL: URL) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let storeURL = directoryURL.appendingPathComponent("store.sqlite")

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
