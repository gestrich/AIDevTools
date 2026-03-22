import MarkdownUI
import PlanRunnerFeature
import PlanRunnerService
import RepositorySDK
import SwiftUI

struct PlanDetailView: View {
    @Environment(PlanRunnerModel.self) var planRunnerModel
    let plan: PlanEntry
    let repository: RepositoryInfo

    @State private var planContent: String?
    @State private var localPhases: [PlanPhase] = []
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if case .error(let error) = planRunnerModel.state {
                errorBanner(error)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        phaseSection

                        if case .executing(let progress) = planRunnerModel.state,
                           !progress.currentOutput.isEmpty {
                            outputPanel(progress.currentOutput)
                                .id("live-output")
                        }

                        if case .completed(let result) = planRunnerModel.state {
                            completionBanner(result)
                        }

                        if let planContent {
                            Divider()
                            Markdown(planContent)
                                .markdownTheme(.gitHub.text {
                                    ForegroundColor(.primary)
                                    FontSize(14)
                                })
                                .textSelection(.enabled)
                        } else if let loadError {
                            ContentUnavailableView(
                                "Failed to Load Plan",
                                systemImage: "exclamationmark.triangle",
                                description: Text(loadError)
                            )
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: executionOutput) {
                    proxy.scrollTo("live-output", anchor: .bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(plan.name)
        .task(id: plan.id) {
            loadPlan()
        }
        .onChange(of: planRunnerModel.executionCompleteCount) {
            loadPlan()
        }
    }

    // MARK: - Header

    private var isExecuting: Bool {
        if case .executing = planRunnerModel.state { return true }
        return false
    }

    private var isGenerating: Bool {
        if case .generating = planRunnerModel.state { return true }
        return false
    }

    private var isBusy: Bool { isExecuting || isGenerating }

    private var executionOutput: String {
        if case .executing(let progress) = planRunnerModel.state {
            return progress.currentOutput
        }
        return ""
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            if isExecuting {
                ProgressView()
                    .controlSize(.small)
                executionStatusText
            } else {
                Text(plan.relativePath(to: repository.path))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            if case .executing(let progress) = planRunnerModel.state, progress.totalPhases > 0 {
                Text("\(progress.phasesCompleted)/\(progress.totalPhases) phases")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Button {
                completePlan()
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            .disabled(isBusy)

            Button {
                Task {
                    await planRunnerModel.execute(plan: plan, repository: repository)
                }
            } label: {
                Label("Execute", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .padding()
    }

    @ViewBuilder
    private var executionStatusText: some View {
        if case .executing(let progress) = planRunnerModel.state {
            if let index = progress.currentPhaseIndex {
                Text("Phase \(index + 1): \(progress.currentPhaseDescription)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("Fetching status...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Phases

    @ViewBuilder
    private var phaseSection: some View {
        if case .executing(let progress) = planRunnerModel.state, !progress.phases.isEmpty {
            executionPhaseList(progress)
        } else if !localPhases.isEmpty {
            localPhaseList
        }
    }

    private var localPhaseList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phases")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(localPhases) { phase in
                HStack(spacing: 8) {
                    Button {
                        togglePhase(at: phase.index)
                    } label: {
                        Image(systemName: phase.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(phase.isCompleted ? .green : .secondary)
                    }
                    .buttonStyle(.plain)

                    Text(phase.description)
                        .font(.body)
                        .strikethrough(phase.isCompleted, color: .secondary)
                        .foregroundStyle(phase.isCompleted ? .secondary : .primary)
                }
            }
        }
    }

    private func executionPhaseList(_ progress: PlanRunnerModel.ExecutionProgress) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phases")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(Array(progress.phases.enumerated()), id: \.offset) { index, phase in
                HStack(spacing: 8) {
                    if index == progress.currentPhaseIndex {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: phase.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(phase.isCompleted ? .green : .secondary)
                    }
                    Text(phase.description)
                        .font(.body)
                        .foregroundStyle(index == progress.currentPhaseIndex ? .primary : (phase.isCompleted ? .secondary : .primary))
                }
            }
        }
    }

    // MARK: - Output Panel

    private func outputPanel(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live Output")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            ScrollView {
                Text(text)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 200, maxHeight: 400)
            .background(.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    // MARK: - Completion / Error

    private func completionBanner(_ result: ExecutePlanUseCase.Result) -> some View {
        HStack(spacing: 8) {
            Image(systemName: result.allCompleted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(result.allCompleted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(result.allCompleted ? "All phases completed" : "Execution stopped")
                    .font(.subheadline.bold())
                Text("\(result.phasesExecuted)/\(result.totalPhases) phases in \(formattedTime(result.totalSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") {
                planRunnerModel.reset()
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(result.allCompleted ? .green.opacity(0.1) : .orange.opacity(0.1))
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
                planRunnerModel.reset()
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.red.opacity(0.1))
    }

    // MARK: - Actions

    private func togglePhase(at index: Int) {
        do {
            let updatedContent = try planRunnerModel.togglePhase(plan: plan, phaseIndex: index)
            planContent = updatedContent
            localPhases = PlanRunnerModel.parsePhases(from: updatedContent)
        } catch {
            planRunnerModel.state = .error(error)
        }
    }

    private func completePlan() {
        do {
            try planRunnerModel.completePlan(plan, repository: repository)
        } catch {
            planRunnerModel.state = .error(error)
        }
    }

    // MARK: - Helpers

    private func loadPlan() {
        do {
            let content = try String(contentsOf: plan.planURL, encoding: .utf8)
            planContent = content
            localPhases = PlanRunnerModel.parsePhases(from: content)
            loadError = nil
        } catch {
            planContent = nil
            localPhases = []
            loadError = error.localizedDescription
        }
    }

    private func formattedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}
