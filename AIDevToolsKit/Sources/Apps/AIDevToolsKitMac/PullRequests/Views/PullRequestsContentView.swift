import PRRadarModelsService
import RepositorySDK
import SwiftUI

struct PullRequestsContentView: View {

    let repository: RepositoryConfiguration

    @Environment(WorkspaceModel.self) private var workspaceModel
    @State private var model: PullRequestsModel?
    @State private var selectedPR: PRMetadata?

    var body: some View {
        HSplitView {
            prListView
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if let pr = selectedPR {
                        Task { await model?.refresh(number: pr.number) }
                    } else {
                        Task { await model?.load() }
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help(selectedPR != nil ? "Refresh selected PR" : "Reload all PRs")
                .disabled(model == nil)
            }
        }
        .task(id: repository.id) {
            selectedPR = nil
            guard let config = workspaceModel.prradarConfig(for: repository) else {
                model = nil
                return
            }
            let newModel = PullRequestsModel(config: config)
            model = newModel
            await newModel.load()
        }
    }

    // MARK: - PR List

    private var prListView: some View {
        Group {
            if let model {
                prList(model: model)
            } else {
                ContentUnavailableView(
                    "Not Configured",
                    systemImage: "eye.slash",
                    description: Text("Configure this repository's PR Radar settings in Settings → Repositories.")
                )
            }
        }
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func prList(model: PullRequestsModel) -> some View {
        if case .loading = model.state {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .failed(let message, let prior) = model.state, prior == nil {
            ContentUnavailableView(
                "Load Failed",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        } else if let prs = model.prs, !prs.isEmpty {
            List(prs, selection: $selectedPR) { pr in
                PullRequestsRowView(
                    metadata: pr,
                    isFetching: model.fetchingPRNumbers.contains(pr.number)
                )
                .tag(pr)
            }
            .listStyle(.sidebar)
            .accessibilityIdentifier("pullRequestList")
        } else {
            ContentUnavailableView(
                "No Pull Requests",
                systemImage: "doc.text.magnifyingglass",
                description: Text("No pull requests found.")
            )
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if let pr = selectedPR {
            PullRequestsDetailView(metadata: pr)
        } else {
            ContentUnavailableView(
                "Select a Pull Request",
                systemImage: "arrow.left",
                description: Text("Choose a pull request from the list.")
            )
        }
    }
}
