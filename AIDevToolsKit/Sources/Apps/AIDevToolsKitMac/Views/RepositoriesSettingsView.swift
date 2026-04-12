import PlanService
import RepositorySDK
import SwiftUI

struct RepositoriesSettingsView: View {
    let workspaceModel: WorkspaceModel
    @Binding var editingConfig: RepositoryConfiguration?
    @Binding var isAddingNew: Bool
    @Binding var currentError: Error?
    @State private var selectedConfigId: UUID?
    @State private var configIdToDelete: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                if workspaceModel.repositories.isEmpty {
                    ContentUnavailableView(
                        "No Repositories",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Click + to add a repository.")
                    )
                } else {
                    List(selection: $selectedConfigId) {
                        ForEach(workspaceModel.repositories) { repo in
                            Text(repo.name)
                                .tag(repo.id)
                        }
                    }
                    .onChange(of: selectedConfigId) { _, newValue in
                        if newValue == nil, let first = workspaceModel.repositories.first {
                            selectedConfigId = first.id
                        }
                    }
                }

                Divider()

                HStack(spacing: 6) {
                    Button {
                        isAddingNew = true
                        editingConfig = RepositoryConfiguration(
                            path: URL(filePath: "/"),
                            name: ""
                        )
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        if let configId = selectedConfigId {
                            configIdToDelete = configId
                        }
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(selectedConfigId == nil)

                    Spacer()
                }
                .padding(6)
            }
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 250)

            Group {
                if let selectedConfigId,
                   let config = workspaceModel.repositories.first(where: { $0.id == selectedConfigId }) {
                    ConfigurationDetailView(
                        config: config,
                        casesDirectory: workspaceModel.casesDirectory(for: config),
                        completedDirectory: workspaceModel.completedDirectory(for: config),
                        proposedDirectory: workspaceModel.proposedDirectory(for: config),
                        onEdit: { editingConfig = config }
                    )
                } else {
                    ContentUnavailableView(
                        "Select a Repository",
                        systemImage: "folder",
                        description: Text("Choose a repository from the list.")
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            if selectedConfigId == nil, let first = workspaceModel.repositories.first {
                selectedConfigId = first.id
            }
        }
        .confirmationDialog(
            "Delete Repository",
            isPresented: Binding(
                get: { configIdToDelete != nil },
                set: { if !$0 { configIdToDelete = nil } }
            ),
            presenting: configIdToDelete.flatMap { id in
                workspaceModel.repositories.first(where: { $0.id == id })
            }
        ) { config in
            Button("Delete", role: .destructive) {
                workspaceModel.removeRepository(id: config.id)
                selectedConfigId = nil
                configIdToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                configIdToDelete = nil
            }
        } message: { config in
            Text("Are you sure you want to delete '\(config.name)'?")
        }
    }
}

// MARK: - Configuration Detail View

private struct ConfigurationDetailView: View {
    let config: RepositoryConfiguration
    let casesDirectory: String?
    let completedDirectory: String?
    let proposedDirectory: String?
    let onEdit: () -> Void

    var body: some View {
        Form {
            Section("General") {
                detailRow("Name", value: config.name)
                detailRow("Repo Path", value: config.path.path(percentEncoded: false))
                detailRow("Description", value: config.description)
                detailRow("Credential Account", value: config.credentialAccount)
            }

            if config.recentFocus != nil || config.skills != nil || config.architectureDocs != nil || config.verification != nil {
                Section("Chains") {
                    detailRow("Recent Focus", value: config.recentFocus)
                    detailRow("Skills", value: config.skills?.joined(separator: ", "))
                    detailRow("Architecture Docs", value: config.architectureDocs?.joined(separator: ", "))
                    if let verification = config.verification {
                        detailRow("Verification Commands", value: verification.commands.joined(separator: ", "))
                        detailRow("Verification Notes", value: verification.notes)
                    }
                }
            }

            if casesDirectory != nil {
                Section("Evals") {
                    detailRow("Cases Directory", value: casesDirectory)
                }
            }

            Section("Plans") {
                detailRow("Proposed Plans", value: proposedDirectory, fallback: PlanRepoSettings.defaultProposedDirectory)
                detailRow("Completed Plans", value: completedDirectory, fallback: PlanRepoSettings.defaultCompletedDirectory)
            }

            if let prradar = config.prradar {
                Section("PR Radar") {
                    detailRow("Rule Paths", value: prradar.rulePaths.map { "\($0.name):\($0.path)" }.joined(separator: ", "))
                    detailRow("Diff Source", value: prradar.diffSource.displayName)
                }
            }

            if let pr = config.pullRequest {
                Section("Pull Requests") {
                    detailRow("Base Branch", value: pr.baseBranch)
                    detailRow("Branch Naming", value: pr.branchNamingConvention)
                    detailRow("Template", value: pr.template)
                    detailRow("Notes", value: pr.notes)
                }
            }

            Section {
                Button("Edit") {
                    onEdit()
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailRow(_ label: String, value: String?, fallback: String = "Not configured") -> some View {
        LabeledContent(label) {
            Text(value ?? fallback)
                .foregroundStyle(value != nil ? .secondary : .tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
