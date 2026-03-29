import ClaudeChainFeature
import RepositorySDK
import SwiftUI

struct ClaudeChainView: View {
    @Environment(ClaudeChainModel.self) var model

    let repository: RepositoryInfo

    @State private var selectedProject: ChainProject?

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                ContentUnavailableView("No Chains Loaded", systemImage: "link")
            case .loadingChains:
                ProgressView("Loading chains...")
            case .loaded(let projects):
                if projects.isEmpty {
                    ContentUnavailableView(
                        "No Chains Found",
                        systemImage: "link",
                        description: Text("No claude-chain projects found in this repository.")
                    )
                } else {
                    chainContent(projects: projects)
                }
            case .executing(let progress):
                VStack(spacing: 12) {
                    ProgressView()
                    if !progress.taskDescription.isEmpty {
                        Text("Executing: \(progress.taskDescription)")
                            .font(.headline)
                    }
                    Text(progress.currentPhase)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .completed(let result):
                VStack(spacing: 12) {
                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(result.success ? .green : .red)
                    Text(result.message)
                        .font(.headline)
                    if let prURL = result.prURL {
                        Text(prURL)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .error(let error):
                ContentUnavailableView(
                    "Error",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error.localizedDescription)
                )
            }
        }
        .navigationTitle("Claude Chain")
    }

    @ViewBuilder
    private func chainContent(projects: [ChainProject]) -> some View {
        HSplitView {
            List(projects, id: \.name, selection: $selectedProject) { project in
                ChainProjectRow(project: project)
                    .tag(project)
            }
            .frame(minWidth: 200, idealWidth: 250)

            if let project = selectedProject {
                ChainProjectDetailView(project: project, repository: repository)
            } else {
                ContentUnavailableView(
                    "Select a Chain",
                    systemImage: "link",
                    description: Text("Choose a chain project to view details.")
                )
            }
        }
    }
}

// MARK: - Chain Project Row

private struct ChainProjectRow: View {
    let project: ChainProject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.body)
            HStack(spacing: 4) {
                Text("\(project.completedTasks)/\(project.totalTasks) tasks completed")
                if project.pendingTasks > 0 {
                    Text("\u{00B7}")
                    Text("\(project.pendingTasks) pending")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Chain Project Detail

private struct ChainProjectDetailView: View {
    @Environment(ClaudeChainModel.self) var model

    let project: ChainProject
    let repository: RepositoryInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(project.name)
                    .font(.title2.bold())
                LabeledContent("Spec Path") {
                    Text(project.specPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Progress") {
                    Text("\(project.completedTasks)/\(project.totalTasks) tasks completed")
                }
                if project.pendingTasks > 0 {
                    LabeledContent("Pending") {
                        Text("\(project.pendingTasks) tasks")
                    }
                }
            }

            Divider()

            if project.pendingTasks > 0 {
                Button("Run Next Task") {
                    model.executeChain(projectName: project.name, repoPath: repository.path)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Label("All tasks completed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
