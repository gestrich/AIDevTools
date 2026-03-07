import RepositorySDK
import SwiftUI

struct SettingsView: View {
    @Environment(SettingsModel.self) private var settingsModel
    @Environment(WorkspaceModel.self) private var workspaceModel
    @State private var editingConfig: RepositoryInfo?
    @State private var isAddingNew = false
    @State private var currentError: Error?

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }

            Tab("Repositories", systemImage: "folder") {
                RepositoriesSettingsView(
                    workspaceModel: workspaceModel,
                    editingConfig: $editingConfig,
                    isAddingNew: $isAddingNew,
                    currentError: $currentError
                )
            }
        }
        .tabViewStyle(.tabBarOnly)
        .frame(width: 700, height: 500)
        .alert("Settings Error", isPresented: isErrorPresented, presenting: currentError) { _ in
            Button("OK") { currentError = nil }
        } message: { error in
            Text(error.localizedDescription)
        }
        .sheet(item: $editingConfig) { config in
            ConfigurationEditSheet(
                config: config,
                casesDirectory: workspaceModel.casesDirectory(for: config),
                completedDirectory: workspaceModel.completedDirectory(for: config),
                proposedDirectory: workspaceModel.proposedDirectory(for: config),
                isNew: isAddingNew
            ) { updatedConfig, casesDirectory, completedDirectory, proposedDirectory in
                if isAddingNew {
                    workspaceModel.addRepository(
                        path: updatedConfig.path,
                        name: updatedConfig.name,
                        casesDirectory: casesDirectory,
                        completedDirectory: completedDirectory,
                        proposedDirectory: proposedDirectory
                    )
                } else {
                    workspaceModel.updateRepository(updatedConfig)
                    workspaceModel.updateCasesDirectory(for: updatedConfig.id, casesDirectory: casesDirectory)
                    workspaceModel.updatePlanDirectories(
                        for: updatedConfig.id,
                        proposedDirectory: proposedDirectory,
                        completedDirectory: completedDirectory
                    )
                }
                isAddingNew = false
            } onCancel: {
                isAddingNew = false
            }
        }
    }

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { currentError != nil },
            set: { if !$0 { currentError = nil } }
        )
    }
}
