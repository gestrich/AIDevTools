import AnthropicChatService
import ArchitecturePlannerFeature
import ArchitecturePlannerService
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
    @State private var architecturePlannerModel = ArchitecturePlannerModel()
    @State private var settingsModel: SettingsModel
    @State private var workspaceModel: WorkspaceModel
    @State private var planRunnerModel: PlanRunnerModel

    public init() {
        AIDevToolsLogging.bootstrap()
        let settingsModel = SettingsModel()
        let store = RepositoryStore(repositoriesFile: settingsModel.dataPath.appending(path: "repositories.json"))
        let evalSettingsStore = EvalRepoSettingsStore(filePath: settingsModel.dataPath.appending(path: "eval-settings.json"))
        let planSettingsStore = PlanRepoSettingsStore(filePath: settingsModel.dataPath.appending(path: "plan-settings.json"))
        _settingsModel = State(initialValue: settingsModel)
        _workspaceModel = State(initialValue: WorkspaceModel(
            dataPath: settingsModel.dataPath,
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
            dataPath: settingsModel.dataPath,
            planSettingsStore: planSettingsStore
        ))
    }

    public var body: some View {
        WorkspaceView()
            .environment(architecturePlannerModel)
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
        let store = RepositoryStore(repositoriesFile: settingsModel.dataPath.appending(path: "repositories.json"))
        let evalSettingsStore = EvalRepoSettingsStore(filePath: settingsModel.dataPath.appending(path: "eval-settings.json"))
        let planSettingsStore = PlanRepoSettingsStore(filePath: settingsModel.dataPath.appending(path: "plan-settings.json"))
        _settingsModel = State(initialValue: settingsModel)
        _workspaceModel = State(initialValue: WorkspaceModel(
            dataPath: settingsModel.dataPath,
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
            .task { workspaceModel.load() }
    }
}
