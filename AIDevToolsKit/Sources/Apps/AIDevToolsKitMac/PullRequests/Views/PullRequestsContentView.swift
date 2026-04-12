import PRRadarModelsService
import RepositorySDK
import SwiftUI

struct PullRequestsContentView: View {

    let isActive: Bool
    let repository: RepositoryConfiguration

    @Environment(WorkspaceModel.self) private var workspaceModel
    @State private var model: PullRequestsModel?
    @State private var selectedPRNumber: Int?

    // Always derived from the live model so the detail view sees enriched data as it arrives.
    private var selectedPR: PRMetadata? {
        guard let number = selectedPRNumber else { return nil }
        return model?.prs?.first { $0.number == number }
    }

    var body: some View {
        HSplitView {
            prListView
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            if isActive {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if let number = selectedPRNumber {
                            Task { await model?.refresh(number: number) }
                        } else {
                            Task { await model?.load() }
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help(selectedPRNumber != nil ? "Refresh selected PR" : "Reload all PRs")
                    .disabled(model == nil)
                }
            }
        }
        .task(id: repository.id) {
            selectedPRNumber = nil
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
            List(prs, selection: $selectedPRNumber) { pr in
                let isFetching = model.fetchingPRNumbers.contains(pr.number)
                PullRequestsRowView(metadata: pr, isFetching: isFetching)
                    .tag(pr.number)
                    .id("\(pr.contentID)|\(isFetching)")
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
