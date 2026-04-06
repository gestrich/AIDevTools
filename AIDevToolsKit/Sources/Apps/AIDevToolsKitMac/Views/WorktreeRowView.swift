import SwiftUI
import WorktreeFeature

struct WorktreeRowView: View {
    let status: WorktreeStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(status.name)
                        .fontWeight(.medium)
                    if status.isMain {
                        Text("Main")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
                Text(status.branch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status.hasUncommittedChanges {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 2)
    }
}
