import AIOutputSDK
import EvalSDK
import EvalService
import ProviderRegistryService
import SwiftUI

struct EvalResultsView: View {
    let registry: EvalProviderRegistry
    let hideSuitePicker: Bool
    @Environment(EvalRunnerModel.self) var evalRunnerModel

    init(registry: EvalProviderRegistry, hideSuitePicker: Bool = false) {
        self.registry = registry
        self.hideSuitePicker = hideSuitePicker
    }

    @State private var showDirtyRepoAlert = false
    @State private var pendingRunAction: (() -> Void)?
    @State private var presentedError: Error?

    var body: some View {
        caseListView
            .alert("Outstanding Changes", isPresented: $showDirtyRepoAlert) {
                Button("Continue Anyway", role: .destructive) {
                    pendingRunAction?()
                    pendingRunAction = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingRunAction = nil
                }
            } message: {
                Text("The repository has uncommitted changes that will be lost when edit-mode eval cases run. Are you sure you want to continue?")
            }
            .alert("Error", isPresented: Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })) {
                Button("OK") { presentedError = nil }
            } message: {
                Text(presentedError?.localizedDescription ?? "Unknown error")
            }
    }

    private func runWithDirtyCheck(suite: EvalSuite?, evalCase: EvalCase? = nil, action: @escaping () -> Void) {
        guard evalRunnerModel.hasEditCases(suite: suite, evalCase: evalCase) else {
            action()
            return
        }
        do {
            if try evalRunnerModel.repoHasOutstandingChanges() {
                pendingRunAction = action
                showDirtyRepoAlert = true
            } else {
                action()
            }
        } catch {
            presentedError = error
        }
    }

    // MARK: - Case List View

    private var caseListView: some View {
        VStack(spacing: 0) {
            headerBar
            if case .error(let error, _) = evalRunnerModel.state {
                errorBanner(error)
            }
            if evalRunnerModel.displayedCases.isEmpty {
                Spacer()
                Image(systemName: "play.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No eval cases found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(evalRunnerModel.displayedCases, id: \.id) { evalCase in
                            EvalCaseRow(evalCase: evalCase, registry: registry)
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(evalRunnerModel)
    }

    private var isRunning: Bool {
        if case .running = evalRunnerModel.state { return true }
        return false
    }

    private var activeSuite: EvalSuite? {
        evalRunnerModel.selectedSuite ?? evalRunnerModel.suites.first
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            if !hideSuitePicker, evalRunnerModel.suites.count > 1 {
                Picker("Suite", selection: Binding(
                    get: { evalRunnerModel.selectedSuite?.id },
                    set: { newID in
                        let suite = evalRunnerModel.suites.first { $0.id == newID }
                        evalRunnerModel.selectSuite(suite)
                    }
                )) {
                    Text("All Suites").tag(String?.none)
                    ForEach(evalRunnerModel.suites) { suite in
                        Text(suite.name).tag(Optional(suite.id))
                    }
                }
                .fixedSize()
            }

            Spacer()

            Text("\(evalRunnerModel.displayedCases.count) Cases")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Button {
                evalRunnerModel.clearAllArtifacts()
            } label: {
                Label("Clear Results", systemImage: "trash")
            }
            .disabled(isRunning || evalRunnerModel.state.lastResults.isEmpty)

            RunEvalMenu(providers: registry.entries) { providerFilter in
                runWithDirtyCheck(suite: activeSuite) {
                    Task {
                        await evalRunnerModel.run(
                            providerFilter: providerFilter,
                            suite: activeSuite
                        )
                    }
                }
            }
            .disabled(isRunning)
        }
        .padding()
    }

    private func errorBanner(_ error: Error) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(error.localizedDescription)
                .font(.callout)
            Spacer()
            Button("Dismiss") {
                evalRunnerModel.reset()
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(.red.opacity(0.1))
    }

}

// MARK: - Run Eval Menu (play button with provider disclosure)

private struct RunEvalMenu: View {
    let providers: [EvalProviderEntry]
    let onRun: ([String]?) -> Void

    var body: some View {
        Menu {
            ForEach(providers, id: \.name) { entry in
                Button { onRun([entry.name]) } label: {
                    Label(entry.displayName, systemImage: "play.fill")
                }
            }
            if providers.count > 1 {
                Divider()
                Button { onRun(nil) } label: {
                    Label("All", systemImage: "play.fill")
                }
            }
        } label: {
            Label("Run", systemImage: "play.fill")
        } primaryAction: {
            if let first = providers.first {
                onRun([first.name])
            }
        }
        .buttonStyle(.borderedProminent)
        .menuIndicator(.visible)
    }
}

private struct RunEvalMenuCompact: View {
    let providers: [EvalProviderEntry]
    let onRun: ([String]?) -> Void

    var body: some View {
        Menu {
            ForEach(providers, id: \.name) { entry in
                Button { onRun([entry.name]) } label: {
                    Label(entry.displayName, systemImage: "play.fill")
                }
            }
            if providers.count > 1 {
                Divider()
                Button { onRun(nil) } label: {
                    Label("All", systemImage: "play.fill")
                }
            }
        } label: {
            Image(systemName: "play.fill")
                .font(.callout)
        } primaryAction: {
            if let first = providers.first {
                onRun([first.name])
            }
        }
        .buttonStyle(.borderless)
        .menuIndicator(.visible)
    }
}

// MARK: - Eval Case Row

private struct EvalCaseRow: View {
    @Environment(EvalRunnerModel.self) var evalRunnerModel
    let evalCase: EvalCase
    let registry: EvalProviderRegistry

    @State private var isExpanded = false
    @State private var expandedOutputs: Set<String> = []
    @State private var loadedOutputs: [String: FormattedOutput] = [:]
    @State private var showDirtyRepoAlert = false
    @State private var pendingRunAction: (() -> Void)?
    @State private var presentedError: Error?

    private var caseResults: [(provider: String, result: CaseResult)] {
        evalRunnerModel.lastCaseResults(for: evalCase)
    }

    private var runProgress: EvalRunnerModel.RunProgress? {
        if case .running(let progress, _) = evalRunnerModel.state,
           let currentId = progress.currentCaseId,
           currentId == evalCase.id || currentId.hasSuffix(".\(evalCase.id)") {
            return progress
        }
        return nil
    }

    private var isRunning: Bool {
        if case .running = evalRunnerModel.state { return true }
        return false
    }

    private var overallStatus: CaseStatus {
        if runProgress != nil { return .running }
        guard !caseResults.isEmpty else { return .notRun }
        if caseResults.contains(where: { !$0.result.passed && $0.result.errors.isEmpty && !$0.result.skipped.isEmpty }) {
            return .skipped
        }
        if caseResults.contains(where: { !$0.result.passed }) {
            return .failed
        }
        return .passed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                statusIcon
                Text(evalCase.id)
                    .font(.title3.monospaced())
                if let suite = evalCase.suite {
                    Text(suite)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }
                Spacer()
                providerResultBadges
                RunEvalMenuCompact(providers: registry.entries) { providerFilter in
                    let caseSuite = evalRunnerModel.suites.first { $0.name == evalCase.suite }
                    let suite = evalRunnerModel.selectedSuite ?? caseSuite
                    let action: () -> Void = {
                        Task {
                            await evalRunnerModel.run(
                                providerFilter: providerFilter,
                                suite: suite,
                                evalCase: evalCase
                            )
                        }
                    }
                    guard evalCase.mode == .edit else {
                        action()
                        return
                    }
                    do {
                        if try evalRunnerModel.repoHasOutstandingChanges() {
                            pendingRunAction = action
                            showDirtyRepoAlert = true
                        } else {
                            action()
                        }
                    } catch {
                        presentedError = error
                    }
                }
                .disabled(isRunning)
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            }

            if let progress = runProgress {
                caseProgressBar(progress)
                    .padding(.top, 8)
            }

            if isExpanded {
                expandedContent
                    .padding(.top, 12)
                    .padding(.leading, 28)
            }
        }
        .padding()
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .alert("Outstanding Changes", isPresented: $showDirtyRepoAlert) {
            Button("Continue Anyway", role: .destructive) {
                pendingRunAction?()
                pendingRunAction = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRunAction = nil
            }
        } message: {
            Text("The repository has uncommitted changes that will be lost when this edit-mode eval case runs. Are you sure you want to continue?")
        }
        .alert("Error", isPresented: Binding(get: { presentedError != nil }, set: { if !$0 { presentedError = nil } })) {
            Button("OK") { presentedError = nil }
        } message: {
            Text(presentedError?.localizedDescription ?? "Unknown error")
        }
    }

    private func caseProgressBar(_ progress: EvalRunnerModel.RunProgress) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ProgressView()
                .progressViewStyle(.linear)
            HStack(spacing: 4) {
                Text(progress.provider)
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                if let task = progress.currentTask {
                    Text("— \(task)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch overallStatus {
        case .running:
            ProgressView()
                .controlSize(.small)
                .frame(width: 20, height: 20)
        case .passed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.title3)
        case .skipped:
            Image(systemName: "forward.circle.fill")
                .foregroundStyle(.orange)
                .font(.title3)
        case .notRun:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
    }

    @ViewBuilder
    private var providerResultBadges: some View {
        HStack(spacing: 4) {
            ForEach(caseResults, id: \.provider) { entry in
                HStack(spacing: 2) {
                    Image(systemName: entry.result.passed ? "checkmark" : "xmark")
                        .font(.caption2)
                    Text(entry.provider.prefix(1).uppercased())
                        .font(.caption2.bold())
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(entry.result.passed ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                .foregroundStyle(entry.result.passed ? .green : .red)
                .clipShape(Capsule())
            }
        }
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            definitionSection
            if let progress = runProgress, !progress.currentOutput.isEmpty {
                Divider()
                OutputPanel(
                    title: "Output — \(progress.provider)",
                    text: progress.currentOutput,
                    autoScroll: true
                )
            }
            if !caseResults.isEmpty {
                Divider()
                lastRunSection
            }
        }
    }

    // MARK: Definition

    private var definitionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Definition")
                .font(.headline)
                .foregroundStyle(.secondary)

            DetailSection(label: "Mode", content: evalCase.mode.rawValue)
            if let skills = evalCase.skills, !skills.isEmpty {
                let skillSummary = skills.map { assertion in
                    var parts = [assertion.skill]
                    if assertion.shouldTrigger == true { parts.append("should_trigger") }
                    if assertion.mustBeInvoked == true { parts.append("must_invoke") }
                    if assertion.mustNotBeInvoked == true { parts.append("must_not_invoke") }
                    return parts.joined(separator: " ")
                }.joined(separator: "\n")
                DetailSection(label: "Skills", content: skillSummary)
            }
            if let task = evalCase.task {
                DetailSection(label: "Task", content: task)
            }
            if let input = evalCase.input {
                DetailSection(label: "Input", content: input)
            }
            if let prompt = evalCase.prompt {
                DetailSection(label: "Prompt", content: prompt)
            }
            if let expected = evalCase.expected {
                DetailSection(label: "Expected", content: expected)
            }
            if let mustInclude = evalCase.mustInclude, !mustInclude.isEmpty {
                DetailSection(label: "Must Include", content: mustInclude.joined(separator: "\n"))
            }
            if let mustNotInclude = evalCase.mustNotInclude, !mustNotInclude.isEmpty {
                DetailSection(label: "Must Not Include", content: mustNotInclude.joined(separator: "\n"))
            }
            if let det = evalCase.deterministic {
                deterministicSection(det)
            }
            if let rubric = evalCase.rubric {
                rubricSection(rubric)
            }
        }
    }

    // MARK: Last Run Results

    private var lastRunSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last Run")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(caseResults, id: \.provider) { entry in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: entry.result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(entry.result.passed ? .green : .red)
                        Text(entry.provider.capitalized)
                            .font(.subheadline.bold())
                    }

                    if let response = entry.result.providerResponse, !response.isEmpty {
                        DetailSection(label: "Response", content: response)
                    }

                    if !entry.result.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Errors")
                                .font(.subheadline.bold())
                                .foregroundStyle(.red)
                            ForEach(entry.result.errors, id: \.self) { error in
                                Text(error)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.red)
                            }
                        }
                    }

                    if !entry.result.skillChecks.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Skill Checks")
                                .font(.subheadline.bold())
                                .foregroundStyle(.blue)
                            ForEach(Array(entry.result.skillChecks.enumerated()), id: \.offset) { _, check in
                                Text(check.displayDescription)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.blue)
                            }
                        }
                    }

                    if !entry.result.skipped.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Skipped")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            ForEach(entry.result.skipped, id: \.self) { skip in
                                Text(skip)
                                    .font(.body.monospaced())
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    savedOutputSection(provider: entry.provider)
                }
                .padding(8)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    private func savedOutputSection(provider: String) -> some View {
        let isExpanded = expandedOutputs.contains(provider)
        let output = loadedOutputs[provider]

        return VStack(alignment: .leading, spacing: 4) {
            DisclosureGroup(
                isExpanded: Binding(
                    get: { isExpanded },
                    set: { newValue in
                        if newValue {
                            expandedOutputs.insert(provider)
                            if loadedOutputs[provider] == nil {
                                loadedOutputs[provider] = evalRunnerModel.loadCaseOutput(
                                    for: evalCase,
                                    provider: provider
                                )
                            }
                        } else {
                            expandedOutputs.remove(provider)
                        }
                    }
                )
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if let output {
                        OutputPanel(title: nil, text: output.mainOutput)
                        if let rubric = output.rubricOutput, !rubric.isEmpty {
                            OutputPanel(title: "Rubric Evaluation Output", text: rubric)
                        }
                    } else {
                        Text("No saved output found.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } label: {
                Text("Run Output")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Definition Helpers

    @ViewBuilder
    private func deterministicSection(_ det: DeterministicChecks) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deterministic Checks")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            if let cmds = det.traceCommandContains, !cmds.isEmpty {
                DetailSection(label: "Trace Must Contain", content: cmds.joined(separator: "\n"))
            }
            if let cmds = det.traceCommandNotContains, !cmds.isEmpty {
                DetailSection(label: "Trace Must Not Contain", content: cmds.joined(separator: "\n"))
            }
            if let order = det.traceCommandOrder, !order.isEmpty {
                DetailSection(label: "Trace Command Order", content: order.joined(separator: " \u{2192} "))
            }
            if let max = det.maxCommands {
                DetailSection(label: "Max Commands", content: "\(max)")
            }
            if let max = det.maxRepeatedCommands {
                DetailSection(label: "Max Repeated Commands", content: "\(max)")
            }
            if let files = det.filesExist, !files.isEmpty {
                DetailSection(label: "Files Must Exist", content: files.joined(separator: "\n"))
            }
            if let files = det.filesNotExist, !files.isEmpty {
                DetailSection(label: "Files Must Not Exist", content: files.joined(separator: "\n"))
            }
            if let fileContains = det.fileContains, !fileContains.isEmpty {
                ForEach(fileContains.sorted(by: { $0.key < $1.key }), id: \.key) { file, patterns in
                    DetailSection(label: "File Contains (\(file))", content: patterns.joined(separator: "\n"))
                }
            }
            if let fileNotContains = det.fileNotContains, !fileNotContains.isEmpty {
                ForEach(fileNotContains.sorted(by: { $0.key < $1.key }), id: \.key) { file, patterns in
                    DetailSection(label: "File Not Contains (\(file))", content: patterns.joined(separator: "\n"))
                }
            }
            if let expectedDiff = det.expectedDiff {
                if expectedDiff.noDiff == true {
                    DetailSection(label: "Expected Diff", content: "No Diff Expected")
                }
                if let contains = expectedDiff.contains, !contains.isEmpty {
                    DetailSection(label: "Diff Must Contain", content: contains.joined(separator: "\n"))
                }
                if let notContains = expectedDiff.notContains, !notContains.isEmpty {
                    DetailSection(label: "Diff Must Not Contain", content: notContains.joined(separator: "\n"))
                }
            }
            if let refs = det.referenceFileMustBeRead, !refs.isEmpty {
                DetailSection(label: "Reference File Must Be Read", content: refs.joined(separator: "\n"))
            }
            if let refs = det.referenceFileMustNotBeRead, !refs.isEmpty {
                DetailSection(label: "Reference File Must Not Be Read", content: refs.joined(separator: "\n"))
            }
        }
    }

    @ViewBuilder
    private func rubricSection(_ rubric: RubricConfig) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rubric Grading")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)

            DetailSection(label: "Rubric Prompt", content: rubric.prompt)
            if let pass = rubric.requireOverallPass {
                DetailSection(label: "Require Overall Pass", content: pass ? "Yes" : "No")
            }
            if let score = rubric.minScore {
                DetailSection(label: "Min Score", content: "\(score)")
            }
            if let ids = rubric.requiredCheckIds, !ids.isEmpty {
                DetailSection(label: "Required Check IDs", content: ids.joined(separator: ", "))
            }
        }
    }
}

private enum CaseStatus {
    case passed, failed, skipped, notRun, running
}


private struct DetailSection: View {
    let label: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.headline.weight(.bold))
                .foregroundStyle(.tint)
            Text(content)
                .font(.body.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.fill.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
