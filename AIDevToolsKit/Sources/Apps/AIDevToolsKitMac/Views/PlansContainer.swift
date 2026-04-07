import PlanService
import RepositorySDK
import SwiftUI

struct PlansContainer: View {
    @Environment(PlanModel.self) var planModel
    @Environment(WorkspaceModel.self) var model

    let repository: RepositoryConfiguration

    @AppStorage("selectedPlanName") private var storedPlanName: String = ""
    @State private var selectedPlanName: String?
    @State private var showGenerateSheet = false

    private var selectedPlan: MarkdownPlanEntry? {
        guard let name = selectedPlanName else { return nil }
        return planModel.plans.first(where: { $0.name == name })
    }

    var body: some View {
        HSplitView {
            sidebar
            detail
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: repository.id) {
            await planModel.loadPlans(for: repository)
            if selectedPlanName == nil, !storedPlanName.isEmpty {
                selectedPlanName = storedPlanName
            }
        }
        .onChange(of: selectedPlanName) { _, newValue in
            storedPlanName = newValue ?? ""
        }
        .sheet(isPresented: $showGenerateSheet) {
            GeneratePlanSheet(selectedPlanName: $selectedPlanName)
        }
    }

    private var sidebar: some View {
        WorkspaceSidebar {
            showGenerateSheet = true
        } content: {
            List(selection: $selectedPlanName) {
                if case .loadingPlans = planModel.state {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading plans...").font(.caption).foregroundStyle(.secondary)
                    }
                }

                if case .generating(let step) = planModel.state {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(step).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }

                if case .error(let error) = planModel.state {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red).font(.caption)
                            Text("Generation Failed").font(.caption.bold()).foregroundStyle(.red)
                            Spacer()
                            Button("Dismiss") { planModel.reset() }
                                .font(.caption).buttonStyle(.borderless)
                        }
                        Text(error.localizedDescription)
                            .font(.caption).foregroundStyle(.red).textSelection(.enabled)
                    }
                    .padding(6)
                    .background(.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                ForEach(planModel.plans) { plan in
                    PlanListRow(plan: plan)
                        .tag(plan.name)
                        .contextMenu {
                            Button("Copy Path", systemImage: "doc.on.doc") {
                                copyToClipboard(plan.relativePath(to: repository.path))
                            }
                            Button(role: .destructive) {
                                if selectedPlanName == plan.name { selectedPlanName = nil }
                                try? planModel.deletePlan(plan)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .listStyle(.sidebar)
        }
    }

    private func copyToClipboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    @ViewBuilder
    private var detail: some View {
        if let plan = selectedPlan {
            PlanDetailView(plan: plan, repository: repository)
        } else {
            ContentUnavailableView("Select a Plan", systemImage: "doc.text", description: Text("Choose a plan to view details."))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Plan List Row

private struct PlanListRow: View {
    let plan: MarkdownPlanEntry

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: plan.isFullyCompleted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(plan.isFullyCompleted ? .green : .secondary)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                HStack(spacing: 4) {
                    Text("\(plan.completedPhases)/\(plan.totalPhases) phases")
                    if let date = plan.creationDate {
                        Text("\u{00B7}")
                        Text(date, style: .date)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Generate Plan Sheet

private struct GeneratePlanSheet: View {
    @Environment(WorkspaceModel.self) var model
    @Environment(PlanModel.self) var planModel
    @Environment(\.dismiss) var dismiss

    @Binding var selectedPlanName: String?
    @State private var promptText = ""
    @AppStorage("planGenerateMatchRepo") private var matchRepo = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Generate Plan").font(.headline)

            if let repo = model.selectedRepository, !matchRepo {
                HStack {
                    Text("Repository:").foregroundStyle(.secondary)
                    Text(repo.name).fontWeight(.medium)
                }
            }

            TextField("Describe what you want to build...", text: $promptText, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            Toggle("Match repository from text", isOn: $matchRepo)
                .font(.caption)

            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Generate") {
                    let text = promptText
                    let repos = model.repositories
                    let selected = matchRepo ? nil : model.selectedRepository
                    dismiss()
                    Task {
                        if let planName = await planModel.generate(prompt: text, repositories: repos, selectedRepository: selected) {
                            selectedPlanName = planName
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 400)
    }
}
