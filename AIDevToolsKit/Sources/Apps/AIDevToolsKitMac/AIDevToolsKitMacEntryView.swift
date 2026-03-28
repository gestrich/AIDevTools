import ArchitecturePlannerFeature
import ArchitecturePlannerService
import DataPathsService
import EvalService
import LoggingSDK
import MarkdownPlannerFeature
import MarkdownPlannerService
import ProviderRegistryService
import RepositorySDK
import SkillBrowserFeature
import SkillScannerSDK
import SkillService
import SwiftUI

public struct AIDevToolsKitMacEntryView: View {
    @State private var architecturePlannerModel: ArchitecturePlannerModel
    @State private var markdownPlannerModel: MarkdownPlannerModel
    @State private var providerModel: ProviderModel
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel
    private let evalProviderRegistry: EvalProviderRegistry

    public init() {
        AIDevToolsLogging.bootstrap()
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _settingsModel = State(initialValue: root.settingsModel)
        _providerModel = State(initialValue: root.providerModel)
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
        let storedPlannerProviderName = UserDefaults.standard.string(forKey: "mdPlannerProviderName")
        _markdownPlannerModel = State(initialValue: MarkdownPlannerModel(
            dataPath: root.settingsModel.dataPath,
            planSettingsStore: root.planSettingsStore,
            providerRegistry: root.providerModel.providerRegistry,
            selectedProviderName: storedPlannerProviderName
        ))
        let storedPlannerProvider = UserDefaults.standard.string(forKey: "archPlannerProviderName")
        _architecturePlannerModel = State(initialValue: ArchitecturePlannerModel(
            dataPathsService: root.dataPathsService,
            providerRegistry: root.providerModel.providerRegistry,
            selectedProviderName: storedPlannerProvider
        ))
        evalProviderRegistry = root.evalProviderRegistry
    }

    public var body: some View {
        WorkspaceView(evalProviderRegistry: evalProviderRegistry)
            .environment(architecturePlannerModel)
            .environment(markdownPlannerModel)
            .environment(providerModel)
            .environment(workspaceModel)
            .frame(minWidth: 800, minHeight: 600)
    }
}

public struct AIDevToolsSettingsView: View {
    @State private var providerModel: ProviderModel
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel

    public init() {
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _providerModel = State(initialValue: root.providerModel)
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
            .environment(providerModel)
            .environment(settingsModel)
            .environment(workspaceModel)
            .task { workspaceModel.load() }
    }
}
