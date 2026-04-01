import AIOutputSDK
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
                        actionItemCount: model.chainDetails[project.name]?.actionItems.count ?? 0,
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
            CreateChainSheet()
        }
    }
}

// MARK: - Chain Project Row

private struct ChainProjectRow: View {
    let project: ChainProject
    let actionItemCount: Int
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
                } else if actionItemCount > 0 {
                    Text("\(actionItemCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
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

    private var chatModel: ChatModel {
        model.persistentChatModel(
            for: project.name,
            workingDirectory: repository.path.path(),
            systemPrompt: makeChainChatSystemPrompt()
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            VSplitView {
                projectContentView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                chatBottomPanel
                    .frame(minHeight: 150, idealHeight: 300, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: project.name) {
            executionChatModel = nil
            model.loadChainDetail(projectName: project.name, repoPath: repository.path)
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
                model.refreshChainDetail(projectName: project.name, repoPath: repository.path)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh GitHub data")
            .disabled(isLoadingGitHub)

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

    private var projectContentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                projectInfoSection

                if let detail = chainDetail, !detail.actionItems.isEmpty {
                    actionItemsBanner(detail.actionItems)
                }

                if let error = chainDetailError {
                    enrichmentErrorBanner(error)
                }

                taskListSection

                if let progress = executionProgress {
                    phaseProgressSection(progress)
                }

                if let result = completedResult {
                    completionBanner(result)
                }

                if let error = errorState {
                    errorBanner(error)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Action Items Banner

    private func actionItemsBanner(_ items: [ChainActionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("\(items.count) action\(items.count == 1 ? "" : "s") needed")
                    .font(.subheadline.bold())
            }
            ForEach(items) { item in
                HStack(spacing: 6) {
                    Image(systemName: actionItemIcon(item.kind))
                        .foregroundStyle(actionItemColor(item.kind))
                        .frame(width: 16)
                    Text(item.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

    private func actionItemIcon(_ kind: ChainActionKind) -> String {
        switch kind {
        case .ciFailure: return "xmark.circle.fill"
        case .draftNeedsReview: return "pencil.circle"
        case .mergeConflict: return "arrow.triangle.merge"
        case .needsReviewers: return "person.badge.plus"
        case .stalePR: return "clock.fill"
        }
    }

    private func actionItemColor(_ kind: ChainActionKind) -> Color {
        switch kind {
        case .ciFailure: return .red
        case .draftNeedsReview: return .blue
        case .mergeConflict: return .red
        case .needsReviewers: return .orange
        case .stalePR: return .orange
        }
    }

    // MARK: - Task List

    private static let statusColumnWidth: CGFloat = 24
    private static let prColumnWidth: CGFloat = 90
    private static let indicatorColumnWidth: CGFloat = 24
    private static let badgeColumnWidth: CGFloat = 58

    private var taskListSection: some View {
        let enrichedTasks = chainDetail?.enrichedTasks
        return VStack(alignment: .leading, spacing: 0) {
            Text("Tasks")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)

            taskListHeader
            Divider()

            ForEach(project.tasks) { task in
                let enrichedPR = enrichedTasks?.first(where: { $0.task.id == task.id })?.enrichedPR
                taskRow(task: task, enrichedPR: enrichedPR)
                Divider()
            }
        }
    }

    private var taskListHeader: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: Self.statusColumnWidth)
            Text("Task")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("PR")
                .frame(width: Self.prColumnWidth, alignment: .trailing)
            Text("Rev")
                .frame(width: Self.indicatorColumnWidth, alignment: .center)
            Text("CI")
                .frame(width: Self.indicatorColumnWidth, alignment: .center)
            Color.clear.frame(width: Self.badgeColumnWidth)
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 4)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func taskRow(task: ChainTask, enrichedPR: EnrichedPR?) -> some View {
        HStack(spacing: 8) {
            taskStatusIcon(task: task)
                .frame(width: Self.statusColumnWidth, alignment: .center)

            Text(task.description)
                .font(.callout)
                .strikethrough(task.isCompleted, color: .secondary)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(task.description)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let pr = enrichedPR {
                prNumberLink(pr, ageLabel: pr.isMerged ? "\(pr.ageDays)d ago" : "\(pr.ageDays)d")
                    .frame(width: Self.prColumnWidth, alignment: .trailing)

                reviewIndicator(pr.reviewStatus)
                    .frame(width: Self.indicatorColumnWidth, alignment: .center)
                    .opacity(pr.isMerged ? 0 : 1)

                buildIndicator(pr.buildStatus)
                    .frame(width: Self.indicatorColumnWidth, alignment: .center)
                    .opacity(pr.isMerged ? 0 : 1)

                prStateBadge(pr)
                    .frame(width: Self.badgeColumnWidth, alignment: .trailing)
            } else {
                Color.clear
                    .frame(width: Self.prColumnWidth + Self.indicatorColumnWidth * 2 + Self.badgeColumnWidth + 24)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
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
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        }
    }

    private func stateBadge(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private func prStateBadge(_ pr: EnrichedPR) -> some View {
        if pr.isMerged {
            stateBadge("MERGED", color: .purple)
        } else if pr.isDraft {
            stateBadge("DRAFT", color: .gray)
        } else {
            Color.clear
        }
    }

    private func prNumberLink(_ pr: EnrichedPR, ageLabel: String) -> some View {
        Button {
            if let urlString = pr.pr.url, let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 3) {
                Text("PR #\(pr.pr.number)")
                    .font(.caption)
                Text(ageLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
    }

    @ViewBuilder
    private func reviewIndicator(_ status: PRReviewStatus) -> some View {
        if !status.approvedBy.isEmpty {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .help("Approved by: \(status.approvedBy.joined(separator: ", "))")
        } else if !status.pendingReviewers.isEmpty {
            Image(systemName: "clock.fill")
                .foregroundStyle(.yellow)
                .help("Pending review: \(status.pendingReviewers.joined(separator: ", "))")
        } else {
            Image(systemName: "person.fill.questionmark")
                .foregroundStyle(.secondary)
                .help("No reviewers assigned")
        }
    }

    @ViewBuilder
    private func buildIndicator(_ status: PRBuildStatus) -> some View {
        switch status {
        case .passing:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("CI passing")
        case .failing(let checks):
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("CI failing: \(checks.joined(separator: ", "))")
        case .pending(let checks):
            Image(systemName: "clock.circle.fill")
                .foregroundStyle(.yellow)
                .help("CI pending: \(checks.joined(separator: ", "))")
        case .conflicting:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .help("Merge conflict")
        case .unknown:
            Image(systemName: "circle.dashed")
                .foregroundStyle(.secondary)
                .help("CI status unknown")
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

    // MARK: - Chat Panel

    @ViewBuilder
    private var chatBottomPanel: some View {
        if let executionModel = executionChatModel, !executionModel.messages.isEmpty {
            VSplitView {
                ChatMessagesView()
                    .environment(executionModel)
                    .frame(minHeight: 80, maxHeight: .infinity)
                ChatPanelView()
                    .environment(chatModel)
                    .frame(minHeight: 80, maxHeight: .infinity)
            }
        } else {
            ChatPanelView()
                .environment(chatModel)
        }
    }

    // MARK: - Execution

    private func startExecution() {
        let execModel = model.makeChatModel(workingDirectory: repository.path.path())
        executionChatModel = execModel

        let accumulator = StreamAccumulator()
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
                Task { await accumulator.reset() }
            case .aiStreamEvent(let event):
                Task {
                    let updatedBlocks = await accumulator.apply(event)
                    await MainActor.run {
                        chatModel.updateCurrentStreamingBlocks(updatedBlocks)
                    }
                }
            case .aiOutput:
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
                Task { await accumulator.reset() }
            case .summaryStreamEvent(let event):
                Task {
                    let updatedBlocks = await accumulator.apply(event)
                    await MainActor.run {
                        chatModel.updateCurrentStreamingBlocks(updatedBlocks)
                    }
                }
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

        model.executeChain(projectName: project.name, repoPath: repository.path)
    }

    private func makeChainChatSystemPrompt() -> String {
        """
        You are an AI assistant embedded in the AIDevTools Mac app, helping the user with a Claude Chain project.
        The chain spec is located at: \(project.specPath)

        You have access to MCP tools: use get_ui_state to check which chain is open and get_chain_status(name:) to see task completion status. Use these tools when the user asks about chain status or progress.
        """
    }
}

// MARK: - Create Chain Sheet

private struct CreateChainSheet: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("New Chain").font(.headline)
            Text("Chain creation is not yet implemented.\nAdd a claude-chain/<name>/spec.md to your repo.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("OK") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding()
        .frame(minWidth: 300)
    }
}
