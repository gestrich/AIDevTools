import SwiftUI

struct MessageBubbleView: View {
    let content: String
    let isUser: Bool
    let timestamp: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isUser ? Color.accentColor : Color(nsColor: .controlBackgroundColor))
                    .foregroundColor(isUser ? .white : .primary)
                    .cornerRadius(12)

                Text(timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }
}
