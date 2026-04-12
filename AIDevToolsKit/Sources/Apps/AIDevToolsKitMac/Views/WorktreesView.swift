import AppKit
import SwiftUI
import WorktreeFeature

struct WorktreesView: View {
    let isActive: Bool

    @Environment(WorktreeModel.self) private var model
    @Environment(WorkspaceModel.self) private var workspaceModel
    @State private var showingAddSheet = false

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                ContentUnavailableView("No Repository Selected", systemImage: "folder")
            case .loading(let prior):
                if let prior {
                    worktreeList(statuses: prior)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            case .loaded(let statuses):
                worktreeList(statuses: statuses)
            case .error(let error, let prior):
                if let prior {
                    worktreeList(statuses: prior)
                } else {
                    ContentUnavailableView(
                        "Failed to Load Worktrees",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error.localizedDescription)
                    )
                }
            }
        }
        .toolbar {
            if isActive {
                ToolbarItem {
                    Button(action: { showingAddSheet = true }) {
                        Label("Add Worktree", systemImage: "plus")
                    }
                    .disabled(workspaceModel.selectedRepository == nil)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            if let repo = workspaceModel.selectedRepository {
                AddWorktreeSheet(
                    repoPath: repo.path.path(percentEncoded: false),
                    model: model
                )
            }
        }
    }

    @ViewBuilder
    private func worktreeList(statuses: [WorktreeStatus]) -> some View {
        List(statuses) { status in
            WorktreeRowView(status: status)
                .contextMenu {
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: status.path)
                    }
                    Button("Open in Terminal") {
                        openInTerminal(path: status.path)
                    }
                    if !status.isMain {
                        Divider()
                        Button("Remove", role: .destructive) {
                            guard let repo = workspaceModel.selectedRepository else { return }
                            Task {
                                await model.removeWorktree(
                                    repoPath: repo.path.path(percentEncoded: false),
                                    worktreePath: status.path
                                )
                            }
                        }
                    }
                }
        }
    }

    private func openInTerminal(path: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", path]
        try? process.run()
    }
}
