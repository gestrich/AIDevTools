import AIOutputSDK
import ClaudeChainFeature
import RepositorySDK
import SwiftUI

struct ClaudeChainView: View {
    @Environment(ClaudeChainModel.self) var model

    let repository: RepositoryInfo

    @State private var selectedProject: ChainProject?

    var body: some View {
        Group {
            switch model.state {
            case .idle:
                ContentUnavailableView("No Chains Loaded", systemImage: "link")
            case .loadingChains where model.lastLoadedProjects.isEmpty:
                ProgressView("Loading chains...")
            default:
                if model.lastLoadedProjects.isEmpty {
                    ContentUnavailableView(
                        "No Chains Found",
                        systemImage: "link",
                        description: Text("No claude-chain projects found in this repository.")
                    )
                } else {
                    chainContent
                }
            }
        }
        .navigationTitle("Claude Chain")
        .onChange(of: model.lastLoadedProjects) { _, newProjects in
            guard !newProjects.isEmpty else { return }
            if let selected = selectedProject {
                selectedProject = newProjects.first(where: { $0.name == selected.name }) ?? newProjects.first
            } else {
                selectedProject = newProjects.first
            }
        }
    }

    @ViewBuilder
    private var chainContent: some View {
        HSplitView {
            List(model.lastLoadedProjects, id: \.name, selection: $selectedProject) { project in
                ChainProjectRow(project: project)
                    .tag(project)
            }
            .frame(minWidth: 200, idealWidth: 250)

            if let project = selectedProject {
                ChainProjectDetailView(project: project, repository: repository)
            } else {
                ContentUnavailableView(
                    "Select a Chain",
                    systemImage: "link",
                    description: Text("Choose a chain project to view details.")
                )
            }
        }
    }
}

// MARK: - Chain Project Row

private struct ChainProjectRow: View {
    let project: ChainProject

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(project.name)
                .font(.body)
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
    let repository: RepositoryInfo

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

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if executionChatModel != nil {
                VSplitView {
                    projectContentView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    chatBottomPanel
                        .frame(minHeight: 150, idealHeight: 300, maxHeight: .infinity)
                }
            } else {
                projectContentView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Picker("Provider", selection: Bindable(model).selectedProviderName) {
                ForEach(model.availableProviders, id: \.name) { provider in
                    Text(provider.displayName).tag(provider.name)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .disabled(isExecuting)

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
        }
    }

    // MARK: - Task List

    private var taskListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Tasks")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(project.tasks) { task in
                HStack(spacing: 8) {
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
                    Text(task.description)
                        .font(.body)
                        .strikethrough(task.isCompleted, color: .secondary)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                }
            }
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
        if let chatModel = executionChatModel {
            ChatMessagesView()
                .environment(chatModel)
        }
    }

    // MARK: - Execution

    private func startExecution() {
        let chatModel = model.makeChatModel(workingDirectory: repository.path.path())
        executionChatModel = chatModel

        let accumulator = StreamAccumulator()
        model.executionProgressObserver = { @MainActor [weak chatModel] progress in
            guard let chatModel else { return }
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
            case .failed(let phase, let error):
                chatModel.finalizeCurrentStreamingMessage()
                chatModel.appendStatusMessage("Failed during \(phase): \(error)")
            }
        }

        model.executeChain(projectName: project.name, repoPath: repository.path)
    }
}
