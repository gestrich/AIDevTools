import ArchitecturePlannerService
import SwiftUI

struct ArchitecturePlannerDetailView: View {
    @Bindable var model: ArchitecturePlannerModel
    let job: PlanningJob
    @AppStorage("archPlannerProviderName") private var storedProviderName: String = ""
    @State private var expandedOutputStepIndex: Int?
    @State private var loadedOutput: String?

    var body: some View {
        VStack(spacing: 0) {
            // Step navigation bar
            stepNavigationBar

            Divider()

            // Main content area
            HSplitView {
                VStack(spacing: 0) {
                    stepDetailView
                        .frame(minWidth: 400)

                    if case .running = model.state, !model.currentOutput.isEmpty {
                        Divider()
                        outputPanel
                    }
                }

                componentsSidebar
                    .frame(minWidth: 250, maxWidth: 350)
            }

            Divider()

            // Action bar
            actionBar
        }
    }

    // MARK: - Step Navigation

    private var stepNavigationBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(sortedSteps, id: \.stepId) { step in
                    StepPill(
                        step: step,
                        isSelected: model.selectedStepIndex == step.stepIndex
                    )
                    .onTapGesture {
                        model.goToStep(step.stepIndex)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.bar)
    }

    private var sortedSteps: [ProcessStep] {
        job.processSteps.sorted(by: { $0.stepIndex < $1.stepIndex })
    }

    // MARK: - Step Detail

    @ViewBuilder
    private var stepDetailView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let stepIdx = model.selectedStepIndex,
                   let step = sortedSteps.first(where: { $0.stepIndex == stepIdx }) {
                    stepContent(step)
                } else if let currentStep = sortedSteps.first(where: { $0.stepIndex == job.currentStepIndex }) {
                    stepContent(currentStep)
                } else {
                    Text("Select a step to view details")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func stepContent(_ step: ProcessStep) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(step.name)
                    .font(.title2)
                    .bold()
                Spacer()
                StatusBadge(status: step.status)
            }

            if !step.summary.isEmpty {
                Text(step.summary)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Show step-specific content
            switch ArchitecturePlannerStep(rawValue: step.stepIndex) {
            case .describeFeature:
                if let request = job.request {
                    Text(request.text)
                        .font(.body)
                }
            case .formRequirements:
                requirementsList
            case .buildImplementationModel, .reviewImplementationPlan:
                implementationComponentsList
            case .finalReport:
                if let report = model.generateReport() {
                    Text(report)
                        .font(.body)
                        .textSelection(.enabled)
                }
            default:
                if step.status == "completed" {
                    Text("Step completed")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Run this step to see results")
                        .foregroundStyle(.secondary)
                }
            }

            if step.status == "completed" {
                stepOutputDisclosure(step)
            }
        }
    }

    @ViewBuilder
    private func stepOutputDisclosure(_ step: ProcessStep) -> some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedOutputStepIndex == step.stepIndex },
                set: { isExpanded in
                    if isExpanded {
                        expandedOutputStepIndex = step.stepIndex
                        loadedOutput = model.loadOutput(jobId: job.jobId, stepIndex: step.stepIndex)
                    } else {
                        expandedOutputStepIndex = nil
                        loadedOutput = nil
                    }
                }
            )
        ) {
            if let loadedOutput, !loadedOutput.isEmpty {
                OutputPanel(title: nil, text: loadedOutput, autoScroll: false)
            } else {
                Text("No output recorded")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } label: {
            Text("Raw Output")
                .font(.subheadline)
        }
    }

    // MARK: - Requirements List

    private var requirementsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Requirements")
                .font(.headline)

            ForEach(job.requirements.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.requirementId) { req in
                HStack(alignment: .top) {
                    Image(systemName: req.isApproved ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(req.isApproved ? .green : .secondary)
                    VStack(alignment: .leading) {
                        Text(req.summary)
                            .font(.body)
                            .bold()
                        if !req.details.isEmpty {
                            Text(req.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Implementation Components

    private var implementationComponentsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Implementation Components")
                .font(.headline)

            ForEach(job.implementationComponents.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.componentId) { comp in
                VStack(alignment: .leading, spacing: 4) {
                    Text(comp.summary)
                        .font(.body)
                        .bold()
                    HStack {
                        Label(comp.layerName, systemImage: "square.stack.3d.up")
                        Label(comp.moduleName, systemImage: "folder")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    // Conformance scores
                    let mappings = comp.guidelineMappings
                    if !mappings.isEmpty {
                        HStack {
                            ForEach(mappings, id: \.mappingId) { mapping in
                                HStack(spacing: 2) {
                                    Text(mapping.guideline?.title ?? "?")
                                        .font(.caption2)
                                    Text("\(mapping.conformanceScore)/10")
                                        .font(.caption2)
                                        .bold()
                                        .foregroundStyle(scoreColor(mapping.conformanceScore))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.quaternary)
                                .cornerRadius(4)
                            }
                        }
                    }

                    // Unclear flags
                    ForEach(comp.unclearFlags, id: \.flagId) { flag in
                        Label(flag.ambiguityDescription, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(8)
                .background(.background.secondary)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Output Panel

    private var outputPanel: some View {
        OutputPanel(title: "Live Output", text: model.currentOutput, autoScroll: true)
            .padding()
    }

    // MARK: - Components Sidebar (Layer View)

    private var componentsSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Layer Map")
                    .font(.headline)
                    .padding(.horizontal)

                let grouped = Dictionary(
                    grouping: job.implementationComponents,
                    by: { $0.layerName }
                )

                ForEach(Array(grouped.keys.sorted()), id: \.self) { layer in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(layer)
                            .font(.subheadline)
                            .bold()
                            .foregroundStyle(.blue)

                        if let comps = grouped[layer] {
                            ForEach(comps.sorted(by: { $0.sortOrder < $1.sortOrder }), id: \.componentId) { comp in
                                HStack {
                                    Circle()
                                        .fill(layerColor(layer))
                                        .frame(width: 8, height: 8)
                                    Text(comp.moduleName)
                                        .font(.caption)
                                    Spacer()
                                    Text("\(comp.filePaths.count) files")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(.background.secondary)
                    .cornerRadius(8)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Picker("Provider", selection: $model.selectedProviderName) {
                ForEach(model.availableProviders, id: \.name) { entry in
                    Text(entry.displayName).tag(entry.name)
                }
            }
            .frame(maxWidth: 200)
            .onChange(of: model.selectedProviderName) { _, newName in
                storedProviderName = newName
            }

            if case .running(let stepName, _) = model.state {
                ProgressView()
                    .controlSize(.small)
                Text(stepName)
                    .foregroundStyle(.secondary)
            } else if case .error(let error) = model.state {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(error.localizedDescription)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .help(error.localizedDescription)
            }

            Spacer()

            Button("Run All Steps") {
                Task { await model.runAllSteps() }
            }
            .disabled(isRunning)

            Button("Run Next Step") {
                Task { await model.runNextStep() }
            }
            .disabled(isRunning)
        }
        .padding()
        .background(.bar)
    }

    private var isRunning: Bool {
        if case .running = model.state { return true }
        return false
    }

    // MARK: - Helpers

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 8...10: return .green
        case 5...7: return .orange
        default: return .red
        }
    }

    private func layerColor(_ layer: String) -> Color {
        switch layer.lowercased() {
        case "apps": return .purple
        case "features": return .blue
        case "services": return .green
        case "sdks": return .orange
        default: return .gray
        }
    }
}

// MARK: - Supporting Views

struct StepPill: View {
    let step: ProcessStep
    let isSelected: Bool

    var body: some View {
        Text(step.name)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(pillBackground)
            .foregroundStyle(pillForeground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
            )
    }

    private var pillBackground: Color {
        switch step.status {
        case "completed": return .green.opacity(0.2)
        case "active": return .blue.opacity(0.2)
        case "stale": return .orange.opacity(0.2)
        default: return .gray.opacity(0.1)
        }
    }

    private var pillForeground: Color {
        switch step.status {
        case "completed": return .green
        case "active": return .blue
        case "stale": return .orange
        default: return .secondary
        }
    }
}

struct StatusBadge: View {
    let status: String

    var body: some View {
        Text(status.capitalized)
            .font(.caption)
            .bold()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .foregroundStyle(foregroundColor)
            .cornerRadius(6)
    }

    private var backgroundColor: Color {
        switch status {
        case "completed": return .green.opacity(0.2)
        case "active": return .blue.opacity(0.2)
        case "stale": return .orange.opacity(0.2)
        default: return .gray.opacity(0.1)
        }
    }

    private var foregroundColor: Color {
        switch status {
        case "completed": return .green
        case "active": return .blue
        case "stale": return .orange
        default: return .secondary
        }
    }
}
