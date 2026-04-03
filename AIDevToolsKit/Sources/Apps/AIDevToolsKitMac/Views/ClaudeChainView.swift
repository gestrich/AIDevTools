import ClaudeChainFeature
import ClaudeChainService
import RepositorySDK
import SwiftUI

struct ClaudeChainView: View {
    @Environment(ClaudeChainModel.self) var model

    let repository: RepositoryConfiguration

    @AppStorage("selectedChainProject") private var storedChainProject: String = ""
    @State private var selectedProject: ChainProject?

    @State private var showCreateSheet = false

    var body: some View {
        HSplitView {
            WorkspaceSidebar {
                showCreateSheet = true
            } content: {
                List(model.lastLoadedProjects, id: \.name, selection: $selectedProject) { project in
                    ChainProjectRow(
                        project: project,
                        actionItemCount: model.chainDetails[project.name]?.actionPRCount ?? 0,
                        openPRCount: model.chainDetails[project.name]?.openPRCount,
                        isLoading: model.chainDetailLoading.contains(project.name)
                    )
                    .tag(project)
                }
                .listStyle(.sidebar)
                .overlay {
                    if case .loadingChains = model.state, model.lastLoadedProjects.isEmpty {
                        ProgressView("Loading chains...")
                    }
                }
            }

            if let project = selectedProject {
                ChainProjectDetailView(project: project, repository: repository)
            } else {
                ContentUnavailableView(
                    "Select a Chain",
                    systemImage: "link",
                    description: Text("Choose a chain project to view details.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: repository.id) {
            model.loadChains(for: repository.path, credentialAccount: repository.credentialAccount)
        }
        .onChange(of: model.lastLoadedProjects) { _, newProjects in
            guard !newProjects.isEmpty else { return }
            if let selected = selectedProject {
                selectedProject = newProjects.first(where: { $0.name == selected.name }) ?? newProjects.first
            } else if !storedChainProject.isEmpty {
                selectedProject = newProjects.first(where: { $0.name == storedChainProject }) ?? newProjects.first
            } else {
                selectedProject = newProjects.first
            }
        }
        .onChange(of: selectedProject) { _, newValue in
            storedChainProject = newValue?.name ?? ""
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateChainSheet(repository: repository)
        }
    }
}

// MARK: - Chain Project Row

private struct ChainProjectRow: View {
    let project: ChainProject
    let actionItemCount: Int
    let openPRCount: Int?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(project.name)
                    .font(.body)
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    // Two fixed-width slots keep badges in consistent columns.
                    // ZStack+Color.clear guarantees the slot width even when empty,
                    // unlike Group{}.frame() which collapses when its content is nil.
                    HStack(spacing: 4) {
                        // Slot 1: open/max PR count (50pt)
                        ZStack(alignment: .trailing) {
                            Color.clear
                            if let openPRCount, project.completedTasks < project.totalTasks {
                                Text("\(openPRCount)/\(min(project.maxOpenPRs ?? 1, project.pendingTasks))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.secondary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .frame(width: 50)

                        // Slot 2: action item count (28pt)
                        ZStack(alignment: .trailing) {
                            Color.clear
                            if actionItemCount > 0 {
                                Text("\(actionItemCount)")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.red)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }
                        .frame(width: 28)
                    }
                }
            }
            ProgressView(value: Double(project.completedTasks), total: max(Double(project.totalTasks), 1))
                .tint(project.completedTasks == project.totalTasks ? .green : .accentColor)
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
    let repository: RepositoryConfiguration

    @AppStorage("chainCreatePR") private var createPR: Bool = true
    @State private var executionChatModel: ChatModel?

    private var isExecuting: Bool {
        if case .executing = model.state { return true }
        return false
    }

    private var executionProgress: ClaudeChainModel.ExecutionProgress? {
        if case .executing(let progress) = model.state { return progress }
        return nil
    }

    private var completedResult: ExecuteChainUseCase.Result? {
        if case .completed(let result) = model.state { return result }
        return nil
    }

    private var errorState: Error? {
        if case .error(let error) = model.state { return error }
        return nil
    }

    private var isLoadingGitHub: Bool {
        model.chainDetailLoading.contains(project.name)
    }

    private var chainDetail: ChainProjectDetail? {
        model.chainDetails[project.name]
    }

    private var chainDetailError: Error? {
        model.chainDetailErrors[project.name]
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            projectContentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: project.name) {
            executionChatModel = nil
            model.loadChainDetail(project: project)
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 12) {
            if isExecuting {
                ProgressView()
                    .controlSize(.small)
                if let progress = executionProgress {
                    Text(progress.currentPhase)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(project.specPath)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if isLoadingGitHub {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading GitHub data...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Picker("Provider", selection: Bindable(model).selectedProviderName) {
                ForEach(model.availableProviders, id: \.name) { provider in
                    Text(provider.displayName).tag(provider.name)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .disabled(isExecuting)

            Button {
                model.refreshChainDetail(project: project)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh GitHub data")
            .disabled(isLoadingGitHub)

            Toggle("Create PR", isOn: $createPR)
                .toggleStyle(.checkbox)
                .disabled(isExecuting)
                .help("When checked, pushes branch and creates a draft PR after the AI completes")

            Button {
                startExecution()
            } label: {
                Label("Run Next Task", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(project.pendingTasks == 0 || isExecuting)
        }
        .padding()
    }

    // MARK: - Content

    @ViewBuilder
    private var projectContentView: some View {
        if isExecuting || executionProgress != nil {
            HSplitView {
                // Left: task list + info
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 16) {
                        projectInfoSection

                        if let error = chainDetailError {
                            enrichmentErrorBanner(error)
                        }
                        if let result = completedResult {
                            completionBanner(result)
                        }
                        if let error = errorState {
                            errorBanner(error)
                        }
                    }
                    .padding()

                    taskListSection

                    Divider()

                    if let progress = executionProgress {
                        phaseProgressSection(progress)
                            .padding()
                    }
                }
                .frame(minWidth: 300, idealWidth: 420, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                // Right: log output (wider)
                if let execModel = executionChatModel {
                    ChatMessagesView()
                        .environment(execModel)
                        .clipShape(RoundedRectangle(cornerRadius: 0))
                        .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    projectInfoSection

                    if let error = chainDetailError {
                        enrichmentErrorBanner(error)
                    }
                    if let result = completedResult {
                        completionBanner(result)
                    }
                    if let error = errorState {
                        errorBanner(error)
                    }
                }
                .padding()

                taskListSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    // MARK: - Project Info

    private var projectInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(project.name)
                .font(.title2.bold())
            LabeledContent("Progress") {
                Text("\(project.completedTasks)/\(project.totalTasks) tasks completed")
            }
            ProgressView(value: Double(project.completedTasks), total: max(Double(project.totalTasks), 1))
                .tint(project.completedTasks == project.totalTasks ? .green : .accentColor)
        }
    }

    private func enrichmentErrorBanner(_ error: Error) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("GitHub enrichment failed: \(error.localizedDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Task List

    private var taskListSection: some View {
        let enrichedTasks = chainDetail?.enrichedTasks
        let pr: (ChainTask) -> EnrichedPR? = { task in
            enrichedTasks?.first(where: { $0.task.description == task.description })?.enrichedPR
        }

        let openTasks = project.tasks.filter { pr($0) != nil && !pr($0)!.isDraft && !pr($0)!.isMerged }
        let draftTasks = project.tasks.filter { pr($0)?.isDraft == true }
        let notStartedTasks = project.tasks.filter { pr($0) == nil && !$0.isCompleted }
        let mergedTasks = project.tasks.filter { pr($0)?.isMerged == true || (pr($0) == nil && $0.isCompleted) }

        return Table(of: ChainTask.self) {
            TableColumn("") { task in
                taskStatusIcon(task: task)
            }
            .width(24)

            TableColumn("Task") { task in
                Text(task.description)
                    .font(.callout)
                    .strikethrough(task.isCompleted, color: .secondary)
                    .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(task.description)
            }

            TableColumn("PR") { task in
                if let enrichedPR = pr(task) {
                    prStatusCell(enrichedPR)
                }
            }
            .width(min: 150, ideal: 180, max: 200)
        } rows: {
            if !openTasks.isEmpty {
                Section("Open") {
                    ForEach(openTasks) { TableRow($0) }
                }
            }
            if !draftTasks.isEmpty {
                Section("Draft") {
                    ForEach(draftTasks) { TableRow($0) }
                }
            }
            if !notStartedTasks.isEmpty {
                Section("Not Started") {
                    ForEach(notStartedTasks) { TableRow($0) }
                }
            }
            if !mergedTasks.isEmpty {
                Section("Merged") {
                    ForEach(mergedTasks) { TableRow($0) }
                }
            }
        }
    }

    @ViewBuilder
    private func taskStatusIcon(task: ChainTask) -> some View {
        if task.isCompleted {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if isExecuting,
                  let progress = executionProgress,
                  task.index == progress.taskIndex {
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        } else {
            Button {
                startExecution(taskIndex: task.index)
            } label: {
                Image(systemName: "play.circle")
                    .foregroundStyle(isExecuting ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)
            .disabled(isExecuting)
            .help("Run this task")
        }
    }

    private func prStatusCell(_ enrichedPR: EnrichedPR) -> some View {
        HStack(spacing: 8) {
            Button {
                if let urlString = enrichedPR.pr.url, let url = URL(string: urlString) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                HStack(spacing: 4) {
                    Text("#\(String(enrichedPR.pr.number))")
                        .font(.caption.monospacedDigit())
                    Text(enrichedPR.isMerged ? "\(enrichedPR.ageDays)d ago" : "\(enrichedPR.ageDays)d")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)

            Spacer()

            if !enrichedPR.isMerged {
                let prActionItems = chainDetail?.actionItems.filter { $0.prNumber == enrichedPR.pr.number } ?? []
                reviewIndicator(enrichedPR.reviewStatus)
                buildIndicator(enrichedPR.buildStatus, actionItems: prActionItems)
            }
        }
    }

    @ViewBuilder
    private func reviewIndicator(_ status: PRReviewStatus) -> some View {
        let count = status.approvedBy.count
        let color: Color = count > 1 ? .green : .gray
        Text("\(count)")
            .font(.caption2.monospacedDigit().bold())
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(color)
            .clipShape(Circle())
            .help(count > 0 ? "Approved by: \(status.approvedBy.joined(separator: ", "))" : "No approvals")
    }

    @ViewBuilder
    private func buildIndicator(_ status: PRBuildStatus, actionItems: [ChainActionItem]) -> some View {
        switch status {
        case .passing:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failing:
            HoverPopover(title: "Issues", items: actionItems.map { $0.message }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
            }
        case .pending:
            HoverPopover(title: "Issues", items: actionItems.map { $0.message }) {
                Image(systemName: "clock.circle.fill")
                    .foregroundStyle(.yellow)
            }
        case .conflicting:
            HoverPopover(title: "Issues", items: actionItems.map { $0.message }) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
        case .unknown:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Phase Progress

    private func phaseProgressSection(_ progress: ClaudeChainModel.ExecutionProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Execution Phases")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(progress.phases) { phase in
                HStack(spacing: 8) {
                    phaseStatusIcon(phase.status)
                    Text(phase.displayName)
                        .font(.body)
                        .foregroundStyle(phaseTextStyle(phase.status))
                }
            }
        }
    }

    @ViewBuilder
    private func phaseStatusIcon(_ status: ClaudeChainModel.PhaseStatus) -> some View {
        switch status {
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 16, height: 16)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func phaseTextStyle(_ status: ClaudeChainModel.PhaseStatus) -> some ShapeStyle {
        switch status {
        case .completed, .skipped:
            return AnyShapeStyle(.secondary)
        case .failed:
            return AnyShapeStyle(.red)
        case .pending, .running:
            return AnyShapeStyle(.primary)
        }
    }

    // MARK: - Completion / Error

    private func completionBanner(_ result: ExecuteChainUseCase.Result) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(result.success ? .green : .red)
            VStack(alignment: .leading) {
                Text(result.message)
                    .font(.subheadline.bold())
                if let prURL = result.prURL {
                    Text(prURL)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if result.isStagingOnly && result.branchName != nil {
                Button {
                    model.createPRFromStaged(project: project, repoPath: repository.path, result: result)
                } label: {
                    Label("Create PR", systemImage: "arrow.up.circle")
                }
                .buttonStyle(.borderedProminent)
            }
            Button("Dismiss") {
                model.reset()
                executionChatModel = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background((result.success ? Color.green : Color.red).opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func errorBanner(_ error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                model.reset()
                executionChatModel = nil
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Execution

    private func startExecution(taskIndex: Int? = nil) {
        let execModel = model.makeChatModel(workingDirectory: repository.path.path())
        executionChatModel = execModel

        model.executionContentBlocksObserver = { @MainActor [weak execModel] blocks in
            execModel?.updateCurrentStreamingBlocks(blocks)
        }

        model.executionProgressObserver = { @MainActor [weak execModel] progress in
            guard let chatModel = execModel else { return }
            switch progress {
            case .preparingProject:
                chatModel.appendStatusMessage("Preparing project...")
            case .preparedTask(let description, let index, let total):
                chatModel.appendStatusMessage("Task \(index + 1)/\(total): \(description)")
            case .runningPreScript:
                chatModel.appendStatusMessage("Running pre-action script...")
            case .preScriptCompleted(let result):
                chatModel.appendStatusMessage(result.success ? "Pre-script completed" : "Pre-script skipped")
            case .runningAI:
                chatModel.finalizeCurrentStreamingMessage()
                chatModel.appendStatusMessage("Starting AI execution...")
                chatModel.beginStreamingMessage()
            case .aiStreamEvent, .aiOutput:
                break
            case .aiCompleted:
                chatModel.finalizeCurrentStreamingMessage()
            case .runningPostScript:
                chatModel.appendStatusMessage("Running post-action script...")
            case .postScriptCompleted(let result):
                chatModel.appendStatusMessage(result.success ? "Post-script completed" : "Post-script skipped")
            case .finalizing:
                chatModel.appendStatusMessage("Finalizing...")
            case .prCreated(let prNumber, let prURL):
                chatModel.appendStatusMessage("PR created: #\(prNumber) \u{2014} \(prURL)")
            case .generatingSummary:
                chatModel.finalizeCurrentStreamingMessage()
                chatModel.appendStatusMessage("Generating PR summary...")
                chatModel.beginStreamingMessage()
            case .summaryStreamEvent:
                break
            case .summaryCompleted:
                chatModel.finalizeCurrentStreamingMessage()
            case .postingPRComment:
                chatModel.appendStatusMessage("Posting PR comment...")
            case .prCommentPosted:
                chatModel.appendStatusMessage("Summary posted to PR")
            case .completed(let prURL):
                chatModel.finalizeCurrentStreamingMessage()
                if let prURL {
                    chatModel.appendStatusMessage("Completed \u{2014} PR: \(prURL)")
                } else {
                    chatModel.appendStatusMessage("Completed")
                }
            case .runningReview:
                chatModel.appendStatusMessage("Running review...")
            case .reviewCompleted(let summary):
                chatModel.appendStatusMessage("Review: \(summary)")
            case .failed(let phase, let error):
                chatModel.finalizeCurrentStreamingMessage()
                chatModel.appendStatusMessage("Failed during \(phase): \(error)")
            }
        }

        model.executeChain(project: project, repoPath: repository.path, taskIndex: taskIndex, stagingOnly: !createPR)
    }

}

// MARK: - Hover Popover

private struct HoverPopover<Label: View>: View {
    let title: String
    let items: [String]
    @ViewBuilder let label: () -> Label

    @State private var isHovered = false
    @State private var showPopover = false

    var body: some View {
        label()
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering {
                    showPopover = true
                } else {
                    Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        if !isHovered { showPopover = false }
                    }
                }
            }
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption.bold())
                    ForEach(items, id: \.self) { item in
                        Text(item)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .frame(maxWidth: 300)
            }
    }
}

// MARK: - Create Chain Sheet

private struct CreateChainSheet: View {
    @Environment(ClaudeChainModel.self) var model
    @Environment(\.dismiss) var dismiss

    let repository: RepositoryConfiguration

    @State private var name = ""
    @State private var baseBranch = "main"
    @State private var creationError: Error?

    var body: some View {
        Form {
            TextField("Project name", text: $name)
            TextField("Base branch", text: $baseBranch)
            if let creationError {
                Text(creationError.localizedDescription)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    do {
                        try model.createProject(name: name, baseBranch: baseBranch)
                        dismiss()
                    } catch {
                        creationError = error
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("New Chain")
        .frame(minWidth: 300)
    }
}
