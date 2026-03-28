import ChatManagerService
import SwiftUI

struct ChatQueueViewerSheet: View {
    @Environment(ChatManager.self) private var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if chatManager.messageQueue.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)

                        Text("No Queued Messages")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Messages sent while processing will appear here")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(chatManager.messageQueue) { queuedMessage in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "clock")
                                        .foregroundStyle(.orange)
                                        .font(.caption)

                                    Text("Queued at \(queuedMessage.timestamp, style: .time)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)

                                    Spacer()

                                    Button(action: {
                                        chatManager.removeQueuedMessage(id: queuedMessage.id)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.red)
                                    }
                                    .buttonStyle(.plain)
                                    .help("Cancel this message")
                                }

                                if !queuedMessage.content.isEmpty {
                                    Text(queuedMessage.content)
                                        .font(.body)
                                        .lineLimit(3)
                                        .truncationMode(.tail)
                                }

                                if !queuedMessage.images.isEmpty {
                                    HStack(spacing: 4) {
                                        Image(systemName: "photo")
                                            .font(.caption)
                                        Text("\(queuedMessage.images.count) image(s)")
                                            .font(.caption)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Queued Messages (\(chatManager.messageQueue.count))")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }

                if !chatManager.messageQueue.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Clear All", role: .destructive) {
                            chatManager.clearQueue()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 300)
    }
}
