import EvalSDK
import EvalService
import ProviderRegistryService
import RepositorySDK
import SwiftUI

struct EvalsContainer: View {
    @Environment(WorkspaceModel.self) var model

    let repository: RepositoryInfo
    let evalProviderRegistry: EvalProviderRegistry

    @AppStorage("selectedEvalSuite") private var storedSuiteName: String = ""
    @State private var selectedSuiteName: String?
    @State private var evalRunnerModel: EvalRunnerModel?

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: repository.id) {
            if let config = model.evalConfig(for: repository) {
                let runner = EvalRunnerModel(config: config, registry: evalProviderRegistry)
                evalRunnerModel = runner
                if selectedSuiteName == nil, !storedSuiteName.isEmpty {
                    selectedSuiteName = storedSuiteName
                }
            } else {
                evalRunnerModel = nil
            }
        }
        .onChange(of: selectedSuiteName) { _, newValue in
            storedSuiteName = newValue ?? ""
            if let runner = evalRunnerModel {
                let suite = runner.suites.first(where: { $0.name == newValue })
                runner.selectSuite(suite)
            }
        }
    }

    private var sidebar: some View {
        WorkspaceSidebar {
            // Evals are discovered from files, no creation action
        } content: {
            List(selection: $selectedSuiteName) {
                if let runner = evalRunnerModel {
                    Text("All Suites")
                        .tag(String?.none as String?)

                    ForEach(runner.suites) { suite in
                        HStack {
                            Text(suite.name)
                            Spacer()
                            Text("\(suite.cases.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(suite.name)
                    }
                }
            }
            .listStyle(.sidebar)
            .overlay {
                if model.evalConfig(for: repository) == nil {
                    ContentUnavailableView("No Evals", systemImage: "checkmark.shield", description: Text("No eval cases configured for this repository."))
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let config = model.evalConfig(for: repository) {
            EvalResultsView(
                config: config,
                skillName: nil,
                registry: evalProviderRegistry
            )
        } else {
            ContentUnavailableView("No Evals Configured", systemImage: "checkmark.shield", description: Text("This repository has no eval cases configured."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
