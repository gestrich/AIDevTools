import SwiftUI

struct PipelineView: View {
    @Environment(PipelineModel.self) var pipelineModel

    var body: some View {
        phaseList
    }

    private var phaseList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Phases")
                .font(.headline)
                .foregroundStyle(.secondary)

            ForEach(pipelineModel.nodes) { node in
                HStack(spacing: 8) {
                    if node.isCurrent {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: node.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(node.isCompleted ? .green : .secondary)
                    }
                    Text(node.displayName)
                        .font(.body)
                        .foregroundStyle(node.isCurrent ? .primary : (node.isCompleted ? .secondary : .primary))
                }
            }
        }
    }
}
