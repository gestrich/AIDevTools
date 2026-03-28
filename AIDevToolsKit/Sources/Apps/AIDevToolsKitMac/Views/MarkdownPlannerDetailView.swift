import MarkdownUI
import MarkdownPlannerFeature
import MarkdownPlannerService
import RepositorySDK
import SwiftUI

struct MarkdownPlannerDetailView: View {
    @Environment(MarkdownPlannerModel.self) var markdownPlannerModel
    let plan: MarkdownPlanEntry
    let repository: RepositoryInfo

    @State private var planContent: String?
    @State private var localPhases: [PlanPhase] = []
    @State private var loadError: String?
    @State private var architectureDiagram: ArchitectureDiagram?
    @State private var selectedModule: ModuleSelection?
    @State private var isArchitectureExpanded = true
    @State private var executeNextOnly = false
    @AppStorage("planStopAfterArchitectureDiagram") private var stopAfterArchitectureDiagram = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            if case .error(let error) = markdownPlannerModel.state {
                errorBanner(error)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        phaseSection

                        if let diagram = architectureDiagram {
                            DisclosureGroup("Architecture", isExpanded: $isArchitectureExpanded) {
                                ArchitectureDiagramView(
                                    diagram: diagram,
                                    selectedModule: $selectedModule
                                )
                            }
                        }

                        if case .executing(let progress) = markdownPlannerModel.state,
                           !progress.currentOutput.isEmpty {
                            outputPanel(progress.currentOutput)
                                .id("live-output")
                        }

                        if case .completed(let result) = markdownPlannerModel.state {
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
        .onChange(of: markdownPlannerModel.phaseCompleteCount) {
            loadArchitectureDiagram()
        }
        .onChange(of: markdownPlannerModel.executionCompleteCount) {
            loadPlan()
        }
    }

    // MARK: - Header

    private var isExecuting: Bool {
        if case .executing = markdownPlannerModel.state { return true }
        return false
    }

    private var isGenerating: Bool {
        if case .generating = markdownPlannerModel.state { return true }
        return false
    }

    private var isBusy: Bool { isExecuting || isGenerating }

    private var executionOutput: String {
        if case .executing(let progress) = markdownPlannerModel.state {
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

            if case .executing(let progress) = markdownPlannerModel.state, progress.totalPhases > 0 {
                Text("\(progress.phasesCompleted)/\(progress.totalPhases) phases")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Picker("Provider", selection: Bindable(markdownPlannerModel).selectedProviderName) {
                ForEach(markdownPlannerModel.availableProviders, id: \.name) { provider in
                    Text(provider.displayName).tag(provider.name)
                }
            }
            .labelsHidden()
            .frame(width: 120)
            .disabled(isBusy)

            Toggle("Next only", isOn: $executeNextOnly)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Execute only the next incomplete phase")

            Toggle("Pause for architecture", isOn: $stopAfterArchitectureDiagram)
                .toggleStyle(.checkbox)
                .font(.caption)
                .help("Stop execution after the architecture diagram is generated")

            Button {
                completePlan()
            } label: {
                Label("Complete", systemImage: "checkmark.circle")
            }
            .disabled(isBusy)

            Button {
                let stopForDiagram = stopAfterArchitectureDiagram
                let mode: ExecutePlanUseCase.ExecuteMode = executeNextOnly ? .next : .all
                Task {
                    await markdownPlannerModel.execute(
                        plan: plan,
                        repository: repository,
                        executeMode: mode,
                        stopAfterArchitectureDiagram: stopForDiagram
                    )
                }
            } label: {
                Label(executeNextOnly ? "Execute Next" : "Execute All", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)
        }
        .padding()
    }

    @ViewBuilder
    private var executionStatusText: some View {
        if case .executing(let progress) = markdownPlannerModel.state {
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
        if case .executing(let progress) = markdownPlannerModel.state, !progress.phases.isEmpty {
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

    private func executionPhaseList(_ progress: MarkdownPlannerModel.ExecutionProgress) -> some View {
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
        OutputPanel(title: "Live Output", text: text, autoScroll: true)
    }

    // MARK: - Completion / Error

    private func completionBanner(_ result: ExecutePlanUseCase.Result) -> some View {
        let bannerIcon: String
        let bannerColor: Color
        let bannerTitle: String
        if result.allCompleted {
            bannerIcon = "checkmark.circle.fill"
            bannerColor = .green
            bannerTitle = "All phases completed"
        } else if result.stoppedForArchitectureReview {
            bannerIcon = "building.columns"
            bannerColor = .blue
            bannerTitle = "Paused for architecture review"
        } else {
            bannerIcon = "exclamationmark.triangle.fill"
            bannerColor = .orange
            bannerTitle = "Execution stopped"
        }

        return HStack(spacing: 8) {
            Image(systemName: bannerIcon)
                .foregroundStyle(bannerColor)
            VStack(alignment: .leading) {
                Text(bannerTitle)
                    .font(.subheadline.bold())
                Text("\(result.phasesExecuted)/\(result.totalPhases) phases in \(formattedTime(result.totalSeconds))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Dismiss") {
                markdownPlannerModel.reset()
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(bannerColor.opacity(0.1))
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
                markdownPlannerModel.reset()
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.red.opacity(0.1))
    }

    // MARK: - Actions

    private func togglePhase(at index: Int) {
        do {
            let updatedContent = try markdownPlannerModel.togglePhase(plan: plan, phaseIndex: index)
            planContent = updatedContent
            localPhases = MarkdownPlannerModel.parsePhases(from: updatedContent)
        } catch {
            markdownPlannerModel.state = .error(error)
        }
    }

    private func completePlan() {
        do {
            try markdownPlannerModel.completePlan(plan, repository: repository)
        } catch {
            markdownPlannerModel.state = .error(error)
        }
    }

    // MARK: - Helpers

    private func loadPlan() {
        do {
            let content = try String(contentsOf: plan.planURL, encoding: .utf8)
            planContent = content
            localPhases = MarkdownPlannerModel.parsePhases(from: content)
            loadError = nil
        } catch {
            planContent = nil
            localPhases = []
            loadError = error.localizedDescription
        }

        loadArchitectureDiagram()
    }

    private func loadArchitectureDiagram() {
        let planName = plan.planURL.deletingPathExtension().lastPathComponent
        let architectureURL = plan.planURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(planName)-architecture.json")
        if let data = try? Data(contentsOf: architectureURL) {
            architectureDiagram = try? JSONDecoder().decode(ArchitectureDiagram.self, from: data)
        } else {
            architectureDiagram = nil
        }
        selectedModule = nil
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
