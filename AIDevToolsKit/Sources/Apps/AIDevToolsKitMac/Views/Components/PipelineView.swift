import MarkdownPlannerService
import SwiftUI

struct PipelineView: View {
    let phases: [PlanPhase]
    let currentPhaseIndex: Int?

    var body: some View {
        phaseList
    }

    private var phaseList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phases")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(phases) { phase in
                HStack(spacing: 8) {
                    if phase.index == currentPhaseIndex {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: phase.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(phase.isCompleted ? .green : .secondary)
                    }
                    Text(phase.description)
                        .font(.body)
                        .foregroundStyle(phase.index == currentPhaseIndex ? .primary : (phase.isCompleted ? .secondary : .primary))
                }
            }
        }
    }
}
