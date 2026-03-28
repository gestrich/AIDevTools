import AnthropicChatService
import ArchitecturePlannerFeature
import ArchitecturePlannerService
import DataPathsService
import EvalService
import LoggingSDK
import PlanRunnerFeature
import PlanRunnerService
import ProviderRegistryService
import RepositorySDK
import SkillBrowserFeature
import SkillScannerSDK
import SkillService
import SwiftData
import SwiftUI

public struct AIDevToolsKitMacEntryView: View {
    @State private var architecturePlannerModel: ArchitecturePlannerModel
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel
    @State private var planRunnerModel: PlanRunnerModel
    private let providerRegistry: ProviderRegistry
    private let evalProviderRegistry: EvalProviderRegistry

    public init() {
        AIDevToolsLogging.bootstrap()
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _settingsModel = State(initialValue: root.settingsModel)
        _workspaceModel = State(initialValue: WorkspaceModel(
            dataPath: root.settingsModel.dataPath,
            repoStore: root.repositoryStore,
            evalSettingsStore: root.evalSettingsStore,
            planSettingsStore: root.planSettingsStore,
            loadRepositories: LoadRepositoriesUseCase(store: root.repositoryStore),
            loadSkills: LoadSkillsUseCase(),
            addRepository: AddRepositoryUseCase(store: root.repositoryStore),
            removeRepository: RemoveRepositoryUseCase(store: root.repositoryStore),
            updateRepository: UpdateRepositoryUseCase(store: root.repositoryStore)
        ))
        _planRunnerModel = State(initialValue: PlanRunnerModel(
            dataPath: root.settingsModel.dataPath,
            planSettingsStore: root.planSettingsStore
        ))
        let defaultClient = root.providerRegistry.providers.first!
        _architecturePlannerModel = State(initialValue: ArchitecturePlannerModel(
            dataPathsService: root.dataPathsService,
            client: defaultClient
        ))
        providerRegistry = root.providerRegistry
        evalProviderRegistry = root.evalProviderRegistry
    }

    public var body: some View {
        WorkspaceView(providerRegistry: providerRegistry, evalProviderRegistry: evalProviderRegistry)
            .environment(architecturePlannerModel)
            .environment(planRunnerModel)
            .environment(workspaceModel)
            .modelContainer(for: [ChatConversation.self, ChatMessage.self])
    }
}

public struct AIDevToolsSettingsView: View {
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel

    public init() {
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _settingsModel = State(initialValue: root.settingsModel)
        _workspaceModel = State(initialValue: WorkspaceModel(
            dataPath: root.settingsModel.dataPath,
            repoStore: root.repositoryStore,
            evalSettingsStore: root.evalSettingsStore,
            planSettingsStore: root.planSettingsStore,
            loadRepositories: LoadRepositoriesUseCase(store: root.repositoryStore),
            loadSkills: LoadSkillsUseCase(),
            addRepository: AddRepositoryUseCase(store: root.repositoryStore),
            removeRepository: RemoveRepositoryUseCase(store: root.repositoryStore),
            updateRepository: UpdateRepositoryUseCase(store: root.repositoryStore)
        ))
    }

    public var body: some View {
        SettingsView()
            .environment(settingsModel)
            .environment(workspaceModel)
            .task { workspaceModel.load() }
    }
}
