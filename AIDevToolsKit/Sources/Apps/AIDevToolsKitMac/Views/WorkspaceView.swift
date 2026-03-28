import AIOutputSDK
import ArchitecturePlannerService
import MarkdownPlannerService
import ProviderRegistryService
import RepositorySDK
import SkillService
import SwiftUI

enum WorkspaceItem: Hashable {
    case architecturePlanner
    case evals
    case plan(String)
    case skill(String)
}

struct WorkspaceView: View {
    @Environment(ArchitecturePlannerModel.self) var architecturePlannerModel
    @Environment(WorkspaceModel.self) var model
    @Environment(MarkdownPlannerModel.self) var markdownPlannerModel
    @Environment(ProviderModel.self) var providerModel

    let evalProviderRegistry: EvalProviderRegistry

    @AppStorage("selectedArchPlanner") private var storedArchPlanner = false
    @AppStorage("selectedEvalsView") private var storedEvalsView = false
    @AppStorage("selectedRepositoryID") private var storedRepoID: String = ""
    @AppStorage("selectedPlanName") private var storedPlanName: String?
    @AppStorage("selectedSkillName") private var storedSkillName: String?
    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @State private var selectedRepoID: UUID?
    @State private var selectedItem: WorkspaceItem?
    @State private var showGenerateSheet = false

    var body: some View {
        NavigationSplitView {
            List(model.repositories, selection: $selectedRepoID) { repo in
                Text(repo.name)
            }
            .navigationTitle("Repositories")
            .onChange(of: selectedRepoID) { _, newValue in
                storedRepoID = newValue?.uuidString ?? ""
                selectedItem = nil
                if let id = newValue, let repo = model.repositories.first(where: { $0.id == id }) {
                    Task {
                        async let _ = model.selectRepository(repo)
                        async let _ = markdownPlannerModel.loadPlans(for: repo)
                    }
                    architecturePlannerModel.loadJobs(repoName: repo.name, repoPath: repo.path.path())
                }
            }
        } content: {
            if model.selectedRepository != nil {
                List(selection: $selectedItem) {
                    if let repo = model.selectedRepository, model.evalConfig(for: repo) != nil {
                        Section("Evals") {
                            Text("All Evals")
                                .tag(WorkspaceItem.evals)
                        }
                    }

                    Section("Architecture Planner") {
                        Text("Architecture Planner")
                            .tag(WorkspaceItem.architecturePlanner)
                    }

                    Section("Plans") {
                        planListContent
                    }

                    Section("Skills") {
                        if model.isLoadingSkills {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Loading skills...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        ForEach(model.skills, id: \.name) { skill in
                            Text(skill.name)
                                .tag(WorkspaceItem.skill(skill.name))
                        }
                    }
                }
                .navigationTitle(model.selectedRepository?.name ?? "")
                .task(id: model.selectedRepository?.id) {
                    if let repo = model.selectedRepository {
                        await markdownPlannerModel.loadPlans(for: repo)
                    }
                }
                .onChange(of: selectedItem) { _, newValue in
                    switch newValue {
                    case .architecturePlanner:
                        storedArchPlanner = true
                        storedEvalsView = false
                        storedPlanName = nil
                        storedSkillName = nil
                    case .evals:
                        storedArchPlanner = false
                        storedEvalsView = true
                        storedPlanName = nil
                        storedSkillName = nil
                    case .plan(let name):
                        storedArchPlanner = false
                        storedEvalsView = false
                        storedPlanName = name
                        storedSkillName = nil
                    case .skill(let name):
                        storedArchPlanner = false
                        storedEvalsView = false
                        storedPlanName = nil
                        storedSkillName = name
                    case nil:
                        storedArchPlanner = false
                        storedEvalsView = false
                        storedPlanName = nil
                        storedSkillName = nil
                    }
                }
                .sheet(isPresented: $showGenerateSheet) {
                    GeneratePlanSheet(selectedItem: $selectedItem)
                }
            } else {
                ContentUnavailableView("Select a Repository", systemImage: "folder", description: Text("Choose a repository from the sidebar."))
            }
        } detail: {
            detailContentView
        }
        .task {
            model.load()
            if let id = UUID(uuidString: storedRepoID),
               let repo = model.repositories.first(where: { $0.id == id }) {
                selectedRepoID = id
                async let _ = model.selectRepository(repo)
                async let _ = markdownPlannerModel.loadPlans(for: repo)
                architecturePlannerModel.loadJobs(repoName: repo.name, repoPath: repo.path.path())
                if storedArchPlanner {
                    selectedItem = .architecturePlanner
                } else if storedEvalsView {
                    selectedItem = .evals
                } else if let planName = storedPlanName {
                    selectedItem = .plan(planName)
                } else if let skillName = storedSkillName {
                    selectedItem = .skill(skillName)
                }
            }
        }
        .onChange(of: apiKey) { _, _ in
            providerModel.refreshProviders()
        }
    }

    @ViewBuilder
    private var detailContentView: some View {
        if let repo = model.selectedRepository {
            switch selectedItem {
            case .architecturePlanner:
                ArchitecturePlannerView(model: architecturePlannerModel)
            case .evals:
                if let config = model.evalConfig(for: repo) {
                    EvalResultsView(config: config, registry: evalProviderRegistry)
                }
            case .plan(let name):
                if let plan = markdownPlannerModel.plans.first(where: { $0.name == name }) {
                    MarkdownPlannerDetailView(plan: plan, repository: repo)
                }
            case .skill(let name):
                if let skill = model.skills.first(where: { $0.name == name }) {
                    SkillDetailView(
                        skill: skill,
                        evalConfig: model.evalConfig(for: repo),
                        evalRegistry: evalProviderRegistry
                    ) { selectedItem = .evals }
                }
            case nil:
                ContentUnavailableView("Select an Item", systemImage: "doc.text", description: Text("Choose a skill, plan, or eval suite to view details."))
            }
        }
    }

    // MARK: - Plan List Content

    @ViewBuilder
    private var planListContent: some View {
        if markdownPlannerModel.isLoadingPlans {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading plans...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if case .generating(let step) = markdownPlannerModel.state {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(step)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        if case .error(let error) = markdownPlannerModel.state {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text("Generation Failed")
                        .font(.caption.bold())
                        .foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") {
                        markdownPlannerModel.reset()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
            .padding(6)
            .background(.red.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }

        ForEach(markdownPlannerModel.plans) { plan in
            PlanListRow(plan: plan)
                .tag(WorkspaceItem.plan(plan.name))
                .contextMenu {
                    Button(role: .destructive) {
                        if case .plan(plan.name) = selectedItem {
                            selectedItem = nil
                        }
                        try? markdownPlannerModel.deletePlan(plan)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        }

        Button {
            showGenerateSheet = true
        } label: {
            Image(systemName: "plus")
        }
        .buttonStyle(.plain)
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
    @Environment(MarkdownPlannerModel.self) var markdownPlannerModel
    @Environment(\.dismiss) var dismiss

    @Binding var selectedItem: WorkspaceItem?
    @State private var promptText = ""
    @AppStorage("planGenerateMatchRepo") private var matchRepo = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Generate Plan")
                .font(.headline)

            if let repo = model.selectedRepository, !matchRepo {
                HStack {
                    Text("Repository:")
                        .foregroundStyle(.secondary)
                    Text(repo.name)
                        .fontWeight(.medium)
                }
            }

            TextField("Describe what you want to build...", text: $promptText, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

            Toggle("Match repository from text", isOn: $matchRepo)
                .font(.caption)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Generate") {
                    let text = promptText
                    let repos = model.repositories
                    let selected = matchRepo ? nil : model.selectedRepository
                    dismiss()
                    Task {
                        if let planName = await markdownPlannerModel.generate(prompt: text, repositories: repos, selectedRepository: selected) {
                            selectedItem = .plan(planName)
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
