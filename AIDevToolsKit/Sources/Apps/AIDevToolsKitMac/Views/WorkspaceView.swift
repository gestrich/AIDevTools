import Combine
import ProviderRegistryService
import RepositorySDK
import SwiftUI

struct WorkspaceView: View {
    @Environment(WorkspaceModel.self) var model
    @Environment(ProviderModel.self) var providerModel

    let evalProviderRegistry: EvalProviderRegistry

    @AppStorage("selectedRepositoryID") private var storedRepoID: String = ""
    @AppStorage("selectedWorkspaceTab") private var selectedTab: String = "claudeChain"
    @State private var selectedRepoID: UUID?

    var body: some View {
        NavigationSplitView {
            List(model.repositories, selection: $selectedRepoID) { repo in
                Text(repo.name)
            }
            .navigationTitle("Repositories")
            .onChange(of: selectedRepoID) { _, newValue in
                storedRepoID = newValue?.uuidString ?? ""
                if let id = newValue, let repo = model.repositories.first(where: { $0.id == id }) {
                    Task { await model.selectRepository(repo) }
                }
            }
        } detail: {
            if let repo = model.selectedRepository {
                tabContent(for: repo)
            } else {
                ContentUnavailableView(
                    "Select a Repository",
                    systemImage: "folder",
                    description: Text("Choose a repository from the sidebar.")
                )
            }
        }
        .task {
            model.load()
            if let id = UUID(uuidString: storedRepoID),
               let repo = model.repositories.first(where: { $0.id == id }) {
                selectedRepoID = id
                await model.selectRepository(repo)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .credentialsDidChange)) { _ in
            providerModel.refreshProviders()
        }
    }

    @ViewBuilder
    private func tabContent(for repo: RepositoryInfo) -> some View {
        TabView(selection: $selectedTab) {
            ArchitecturePlannerView(repository: repo)
                .tabItem { Label("Architecture", systemImage: "building.columns") }
                .tag("architecture")

            ClaudeChainView(repository: repo)
                .tabItem { Label("Chains", systemImage: "link") }
                .tag("claudeChain")

            EvalsContainer(repository: repo, evalProviderRegistry: evalProviderRegistry)
                .tabItem { Label("Evals", systemImage: "checkmark.shield") }
                .tag("evals")

            PlansContainer(repository: repo)
                .tabItem { Label("Plans", systemImage: "doc.text") }
                .tag("plans")

            PRRadarContentView(repository: repo)
                .tabItem { Label("PR Radar", systemImage: "eye") }
                .tag("prradar")

            SkillsContainer(repository: repo, evalProviderRegistry: evalProviderRegistry)
                .tabItem { Label("Skills", systemImage: "star") }
                .tag("skills")
        }
    }
}
