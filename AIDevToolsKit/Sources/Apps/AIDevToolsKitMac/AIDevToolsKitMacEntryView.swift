import ArchitecturePlannerFeature
import ArchitecturePlannerService
import DataPathsService
import EvalService
import GitSDK
import PlanFeature
import PlanService
import ProviderRegistryService
import RepositorySDK
import SettingsService
import SkillBrowserFeature
import SkillScannerSDK
import SwiftUI
import WorktreeFeature

public struct AIDevToolsKitMacEntryView: View {
    @State private var appModel: AppModel
    @State private var architecturePlannerModel: ArchitecturePlannerModel
    @State private var claudeChainModel: ClaudeChainModel
    @State private var credentialModel = CredentialModel()
    @State private var ipcServer = AppIPCServer()
    @State private var planModel: PlanModel
    @State private var settingsModel: SettingsModel
    @State private var worktreeModel: WorktreeModel
    @State private var workspaceModel: WorkspaceModel
    private let evalProviderRegistry: EvalProviderRegistry

    public init() {
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _settingsModel = State(initialValue: root.settingsModel)
        let appModel = AppModel(providerModel: root.providerModel)
        _appModel = State(initialValue: appModel)
        let store = root.settingsService.repositoryStore
        let worktreeModel = WorktreeModel(gitClient: root.gitClientFactory(nil))
        _worktreeModel = State(initialValue: worktreeModel)
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
            updateRepository: UpdateRepositoryUseCase(store: store),
            worktreeModel: worktreeModel
        ))
        let storedPlannerProviderName = UserDefaults.standard.string(forKey: "mdPlannerProviderName")
        _planModel = State(initialValue: PlanModel(
            mcpConfigPath: DataPathsService.mcpConfigFileURL.path,
            providerRegistry: appModel.providerModel.providerRegistry,
            selectedProviderName: storedPlannerProviderName
        ))
        let storedPlannerProvider = UserDefaults.standard.string(forKey: "archPlannerProviderName")
        _claudeChainModel = State(initialValue: ClaudeChainModel(
            providerRegistry: appModel.providerModel.providerRegistry,
            dataPathsService: root.dataPathsService,
            gitClientFactory: root.gitClientFactory
        ))
        _architecturePlannerModel = State(initialValue: ArchitecturePlannerModel(
            dataPathsService: root.dataPathsService,
            providerRegistry: appModel.providerModel.providerRegistry,
            selectedProviderName: storedPlannerProvider
        ))
        evalProviderRegistry = root.evalProviderRegistry
    }

    public var body: some View {
        WorkspaceView(evalProviderRegistry: evalProviderRegistry)
            .environment(appModel)
            .environment(appModel.providerModel)
            .environment(architecturePlannerModel)
            .environment(claudeChainModel)
            .environment(credentialModel)
            .environment(planModel)
            .environment(worktreeModel)
            .environment(workspaceModel)
            .frame(minWidth: 800, minHeight: 600)
            .task { await ipcServer.start() }
    }
}

public struct AIDevToolsSettingsView: View {
    @State private var appModel: AppModel
    @State private var credentialModel = CredentialModel()
    @State private var logsModel = LogsModel()
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel

    public init() {
        guard let root = try? CompositionRoot.create() else {
            fatalError("Failed to initialize app services. Check data directory permissions.")
        }
        _appModel = State(initialValue: AppModel(providerModel: root.providerModel))
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
            .environment(appModel)
            .environment(appModel.providerModel)
            .environment(credentialModel)
            .environment(logsModel)
            .environment(settingsModel)
            .environment(workspaceModel)
            .task { workspaceModel.load() }
    }
}
