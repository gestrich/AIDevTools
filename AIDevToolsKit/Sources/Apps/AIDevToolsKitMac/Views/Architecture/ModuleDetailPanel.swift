import PlanRunnerService
import SwiftUI

struct ModuleDetailPanel: View {
    let moduleName: String
    let changes: [ArchitectureChange]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(moduleName)
                    .font(.subheadline.bold())
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ForEach(sortedChanges, id: \.file) { change in
                HStack(spacing: 8) {
                    Circle()
                        .fill(actionColor(change.action))
                        .frame(width: 8, height: 8)

                    Text(actionLabel(change.action))
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .leading)

                    Text(change.file)
                        .font(.caption.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(change.file)

                    Spacer()

                    if let phase = change.phase {
                        Text("Ph.\(phase)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(.separator, lineWidth: 1)
        )
    }

    private var sortedChanges: [ArchitectureChange] {
        changes.sorted {
            let p0 = $0.phase ?? Int.max
            let p1 = $1.phase ?? Int.max
            if p0 != p1 { return p0 < p1 }
            return $0.file < $1.file
        }
    }

    private func actionColor(_ action: ChangeAction) -> Color {
        switch action {
        case .add: return .green
        case .delete: return .red
        case .modify: return .orange
        }
    }

    private func actionLabel(_ action: ChangeAction) -> String {
        switch action {
        case .add: return "add"
        case .delete: return "del"
        case .modify: return "mod"
        }
    }
}
