import ArchitecturePlannerFeature
import ArchitecturePlannerService
import DataPathsService
import EvalService
import MarkdownPlannerFeature
import MarkdownPlannerService
import ProviderRegistryService
import RepositorySDK
import SettingsService
import SkillBrowserFeature
import SkillScannerSDK
import SwiftUI

public struct AIDevToolsKitMacEntryView: View {
    @State private var architecturePlannerModel: ArchitecturePlannerModel
    @State private var claudeChainModel: ClaudeChainModel
    @State private var credentialModel = CredentialModel()
    @State private var ipcServer = AppIPCServer()
    @State private var markdownPlannerModel: MarkdownPlannerModel
    @State private var providerModel: ProviderModel
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel
    private let evalProviderRegistry: EvalProviderRegistry

    public init() {
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _settingsModel = State(initialValue: root.settingsModel)
        _providerModel = State(initialValue: root.providerModel)
        let store = root.settingsService.repositoryStore
        _workspaceModel = State(initialValue: WorkspaceModel(
            dataPath: root.settingsModel.dataPath,
            repositoryStore: store,
            loadRepositories: LoadRepositoriesUseCase(store: store),
            loadSkills: LoadSkillsUseCase(),
            configureNewRepository: ConfigureNewRepositoryUseCase(
                addRepository: AddRepositoryUseCase(store: store),
                repositoryStore: store,
                updateRepository: UpdateRepositoryUseCase(store: store)
            ),
            removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase(
                removeRepository: RemoveRepositoryUseCase(store: store)
            ),
            updateRepository: UpdateRepositoryUseCase(store: store)
        ))
        let storedPlannerProviderName = UserDefaults.standard.string(forKey: "mdPlannerProviderName")
        _markdownPlannerModel = State(initialValue: MarkdownPlannerModel(
            dataPath: root.settingsModel.dataPath,
            mcpConfigPath: DataPathsService.mcpConfigFileURL.path,
            providerRegistry: root.providerModel.providerRegistry,
            selectedProviderName: storedPlannerProviderName
        ))
        let storedPlannerProvider = UserDefaults.standard.string(forKey: "archPlannerProviderName")
        _claudeChainModel = State(initialValue: ClaudeChainModel(
            providerRegistry: root.providerModel.providerRegistry,
            dataPathsService: root.dataPathsService
        ))
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
            .environment(claudeChainModel)
            .environment(credentialModel)
            .environment(markdownPlannerModel)
            .environment(providerModel)
            .environment(workspaceModel)
            .frame(minWidth: 800, minHeight: 600)
            .task { await ipcServer.start() }
    }
}

public struct AIDevToolsSettingsView: View {
    @State private var credentialModel = CredentialModel()
    @State private var logsModel = LogsModel()
    @State private var providerModel: ProviderModel
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel

    public init() {
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _providerModel = State(initialValue: root.providerModel)
        _settingsModel = State(initialValue: root.settingsModel)
        let store = root.settingsService.repositoryStore
        _workspaceModel = State(initialValue: WorkspaceModel(
            dataPath: root.settingsModel.dataPath,
            repositoryStore: store,
            loadRepositories: LoadRepositoriesUseCase(store: store),
            loadSkills: LoadSkillsUseCase(),
            configureNewRepository: ConfigureNewRepositoryUseCase(
                addRepository: AddRepositoryUseCase(store: store),
                repositoryStore: store,
                updateRepository: UpdateRepositoryUseCase(store: store)
            ),
            removeRepositoryWithSettings: RemoveRepositoryWithSettingsUseCase(
                removeRepository: RemoveRepositoryUseCase(store: store)
            ),
            updateRepository: UpdateRepositoryUseCase(store: store)
        ))
    }

    public var body: some View {
        SettingsView()
            .environment(credentialModel)
            .environment(logsModel)
            .environment(providerModel)
            .environment(settingsModel)
            .environment(workspaceModel)
            .task { workspaceModel.load() }
    }
}
