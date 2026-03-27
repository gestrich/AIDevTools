import AnthropicChatService
import AnthropicSDK
import ArchitecturePlannerService
import ClaudeCLISDK
import ClaudeCodeChatService
import PlanRunnerService
import RepositorySDK
import SkillService
import SwiftData
import SwiftUI

enum ChatMode: String, CaseIterable {
    case anthropicAPI = "API"
    case claudeCode = "CLI"
}

enum WorkspaceItem: Hashable {
    case architecturePlanner
    case evals
    case plan(String)
    case skill(String)
}

struct WorkspaceView: View {
    @Environment(ArchitecturePlannerModel.self) var architecturePlannerModel
    @Environment(WorkspaceModel.self) var model
    @Environment(PlanRunnerModel.self) var planRunnerModel

    @AppStorage("selectedArchPlanner") private var storedArchPlanner = false
    @AppStorage("selectedEvalsView") private var storedEvalsView = false
    @AppStorage("selectedRepositoryID") private var storedRepoID: String = ""
    @AppStorage("selectedPlanName") private var storedPlanName: String?
    @AppStorage("selectedSkillName") private var storedSkillName: String?
    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @Environment(\.modelContext) private var modelContext
    @AppStorage("chatPanelVisible") private var chatPanelVisible = false
    @State private var selectedRepoID: UUID?
    @State private var selectedItem: WorkspaceItem?
    @State private var showGenerateSheet = false
    @State private var chatViewModel: ChatViewModel?
    @AppStorage("chatMode") private var chatMode: ChatMode = .claudeCode
    @State private var claudeCodeChatManager: ClaudeCodeChatManager?
    @State private var showingChatSettings = false
    @State private var showingSessionPicker = false

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
                        async let _ = planRunnerModel.loadPlans(for: repo)
                    }
                    architecturePlannerModel.loadJobs(repoName: repo.name, repoPath: repo.path.path())
                }
                rebuildChatViewModel()
                rebuildClaudeCodeChatManager()
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
                        await planRunnerModel.loadPlans(for: repo)
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
                    GeneratePlanSheet()
                }
            } else {
                ContentUnavailableView("Select a Repository", systemImage: "folder", description: Text("Choose a repository from the sidebar."))
            }
        } detail: {
            VStack(spacing: 0) {
                if chatPanelVisible {
                    VSplitView {
                        detailContentView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        VStack(spacing: 0) {
                            chatToolbar
                            chatPanelView
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        .frame(minHeight: 100, idealHeight: 300)
                    }
                } else {
                    detailContentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    bottomBar
                }
            }
            .sheet(isPresented: $showingChatSettings) {
                if let claudeCodeChatManager {
                    ClaudeCodeChatSettingsView()
                        .environment(claudeCodeChatManager)
                }
            }
        }
        .task {
            model.load()
            if let id = UUID(uuidString: storedRepoID),
               let repo = model.repositories.first(where: { $0.id == id }) {
                selectedRepoID = id
                async let _ = model.selectRepository(repo)
                async let _ = planRunnerModel.loadPlans(for: repo)
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
            rebuildChatViewModel()
            rebuildClaudeCodeChatManager()
        }
        .onChange(of: apiKey) { _, _ in
            rebuildChatViewModel()
        }
    }

    // MARK: - Chat

    private var chatToolbar: some View {
        HStack(spacing: 8) {
            Picker("", selection: $chatMode) {
                ForEach(ChatMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 100)

            Spacer()

            if chatMode == .claudeCode, claudeCodeChatManager != nil {
                Button(action: { showingSessionPicker = true }) {
                    Image(systemName: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)
                .help("Session history")
                .popover(isPresented: $showingSessionPicker) {
                    if let claudeCodeChatManager {
                        ClaudeCodeSessionPickerView()
                            .environment(claudeCodeChatManager)
                            .frame(minWidth: 300, minHeight: 400)
                    }
                }

                Button(action: { showingChatSettings = true }) {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
                .help("Claude Code settings")
            }

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { chatPanelVisible = false }
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help("Hide chat")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private var bottomBar: some View {
        HStack {
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { chatPanelVisible = true }
            } label: {
                Image(systemName: "terminal")
            }
            .buttonStyle(.plain)
            .help("Show chat")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }

    @ViewBuilder
    private var detailContentView: some View {
        if let repo = model.selectedRepository {
            switch selectedItem {
            case .architecturePlanner:
                ArchitecturePlannerView(model: architecturePlannerModel)
            case .evals:
                if let config = model.evalConfig(for: repo) {
                    EvalResultsView(config: config)
                }
            case .plan(let name):
                if let plan = planRunnerModel.plans.first(where: { $0.name == name }) {
                    PlanDetailView(plan: plan, repository: repo)
                }
            case .skill(let name):
                if let skill = model.skills.first(where: { $0.name == name }) {
                    SkillDetailView(
                        skill: skill,
                        evalConfig: model.evalConfig(for: repo)
                    ) { selectedItem = .evals }
                }
            case nil:
                ContentUnavailableView("Select an Item", systemImage: "doc.text", description: Text("Choose a skill, plan, or eval suite to view details."))
            }
        }
    }

    @ViewBuilder
    private var chatPanelView: some View {
        switch chatMode {
        case .anthropicAPI:
            if let chatViewModel {
                ChatView(viewModel: chatViewModel)
            } else {
                ContentUnavailableView("API Key Required", systemImage: "key", description: Text("Set your Anthropic API key in Settings to use API chat."))
            }
        case .claudeCode:
            if let claudeCodeChatManager {
                ClaudeCodeChatView()
                    .environment(claudeCodeChatManager)
            } else {
                ContentUnavailableView("Select a Repository", systemImage: "folder", description: Text("Select a repository to start Claude Code chat."))
            }
        }
    }

    private func rebuildChatViewModel() {
        guard !apiKey.isEmpty, model.selectedRepository != nil else {
            chatViewModel = nil
            return
        }
        let anthropicClient = AnthropicAIClient(apiClient: AnthropicAPIClient(apiKey: apiKey))
        chatViewModel = ChatViewModel(
            client: anthropicClient,
            modelContext: modelContext,
            systemPrompt: buildSystemPrompt()
        )
    }

    private func rebuildClaudeCodeChatManager() {
        guard let repo = model.selectedRepository else {
            claudeCodeChatManager = nil
            return
        }
        claudeCodeChatManager = ClaudeCodeChatManager(
            workingDirectory: repo.path.path(),
            client: ClaudeCLIClient()
        )
    }

    private func buildSystemPrompt() -> String {
        guard let repo = model.selectedRepository else {
            return "You are a helpful AI assistant."
        }
        return "You are a helpful AI assistant. The user is working in the repository '\(repo.name)' located at \(repo.path.path())."
    }

    // MARK: - Plan List Content

    @ViewBuilder
    private var planListContent: some View {
        if planRunnerModel.isLoadingPlans {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading plans...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        if case .generating(let step) = planRunnerModel.state {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(step)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }

        if case .error(let error) = planRunnerModel.state {
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
                        planRunnerModel.reset()
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

        ForEach(planRunnerModel.plans) { plan in
            PlanListRow(plan: plan)
                .tag(WorkspaceItem.plan(plan.name))
                .contextMenu {
                    Button(role: .destructive) {
                        if case .plan(plan.name) = selectedItem {
                            selectedItem = nil
                        }
                        try? planRunnerModel.deletePlan(plan)
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
    let plan: PlanEntry

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
                        Text("·")
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
    @Environment(PlanRunnerModel.self) var planRunnerModel
    @Environment(\.dismiss) var dismiss

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
                        await planRunnerModel.generate(prompt: text, repositories: repos, selectedRepository: selected)
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
