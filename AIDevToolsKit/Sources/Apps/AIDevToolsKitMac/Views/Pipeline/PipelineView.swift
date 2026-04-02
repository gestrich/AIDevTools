import SwiftUI

struct PipelineView: View {
    struct Phase: Identifiable {
        let id: Int
        let description: String
        let isCompleted: Bool
    }

    let phases: [Phase]
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
                    if phase.id == currentPhaseIndex {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: phase.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(phase.isCompleted ? .green : .secondary)
                    }
                    Text(phase.description)
                        .font(.body)
                        .foregroundStyle(phase.id == currentPhaseIndex ? .primary : (phase.isCompleted ? .secondary : .primary))
                }
            }
        }
    }
}
