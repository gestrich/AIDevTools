import AnthropicChatService
import EvalFeature
import EvalService
import LoggingSDK
import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK
import SkillBrowserFeature
import SkillScannerSDK
import SkillService
import SwiftData
import SwiftUI

public struct AIDevToolsKitMacEntryView: View {
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel
    @State private var evalRunnerModel = EvalRunnerModel()
    @State private var planRunnerModel: PlanRunnerModel

    public init() {
        AIDevToolsLogging.bootstrap()
        let settingsModel = SettingsModel()
        let config = RepositoryStoreConfiguration(dataPath: settingsModel.dataPath)
        let store = RepositoryStore(configuration: config)
        let evalSettingsStore = EvalRepoSettingsStore(dataPath: settingsModel.dataPath)
        let planSettingsStore = PlanRepoSettingsStore(dataPath: settingsModel.dataPath)
        _settingsModel = State(initialValue: settingsModel)
        _workspaceModel = State(initialValue: WorkspaceModel(
            repoStore: store,
            evalSettingsStore: evalSettingsStore,
            planSettingsStore: planSettingsStore,
            loadRepositories: LoadRepositoriesUseCase(store: store),
            loadSkills: LoadSkillsUseCase(),
            addRepository: AddRepositoryUseCase(store: store),
            removeRepository: RemoveRepositoryUseCase(store: store),
            updateRepository: UpdateRepositoryUseCase(store: store)
        ))
        _planRunnerModel = State(initialValue: PlanRunnerModel(
            planSettingsStore: planSettingsStore
        ))
    }

    public var body: some View {
        WorkspaceView()
            .environment(evalRunnerModel)
            .environment(planRunnerModel)
            .environment(workspaceModel)
            .modelContainer(for: [ChatConversation.self, ChatMessage.self])
    }
}

public struct AIDevToolsSettingsView: View {
    @State private var settingsModel = SettingsModel()
    @State private var workspaceModel: WorkspaceModel

    public init() {
        let settingsModel = SettingsModel()
        let config = RepositoryStoreConfiguration(dataPath: settingsModel.dataPath)
        let store = RepositoryStore(configuration: config)
        let evalSettingsStore = EvalRepoSettingsStore(dataPath: settingsModel.dataPath)
        let planSettingsStore = PlanRepoSettingsStore(dataPath: settingsModel.dataPath)
        _settingsModel = State(initialValue: settingsModel)
        _workspaceModel = State(initialValue: WorkspaceModel(
            repoStore: store,
            evalSettingsStore: evalSettingsStore,
            planSettingsStore: planSettingsStore,
            loadRepositories: LoadRepositoriesUseCase(store: store),
            loadSkills: LoadSkillsUseCase(),
            addRepository: AddRepositoryUseCase(store: store),
            removeRepository: RemoveRepositoryUseCase(store: store),
            updateRepository: UpdateRepositoryUseCase(store: store)
        ))
    }

    public var body: some View {
        SettingsView()
            .environment(settingsModel)
            .environment(workspaceModel)
    }
}
