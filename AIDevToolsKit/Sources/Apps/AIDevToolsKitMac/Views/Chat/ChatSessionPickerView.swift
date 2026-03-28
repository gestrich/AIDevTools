import AIOutputSDK
import ChatManagerService
import ClaudeCLISDK
import SwiftUI

struct ChatSessionPickerView: View {
    @Environment(ChatManager.self) private var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var sessions: [ChatSession] = []
    @State private var isLoading = true
    @State private var selectedSessionForDetail: ChatSession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView("Loading sessions...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)

                        Text("No Previous Sessions")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text("Start a new conversation to create a session")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else {
                    List {
                        ForEach(sessions) { session in
                            HStack {
                                Button(action: {
                                    Task { await chatManager.resumeSession(session.id) }
                                    dismiss()
                                }) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.summary)
                                            .font(.body)
                                            .lineLimit(2)

                                        HStack {
                                            Text(session.lastModified, style: .relative)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)

                                            if chatManager.currentSessionId == session.id {
                                                Spacer()
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundStyle(.green)
                                                    .font(.caption)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(action: { selectedSessionForDetail = session }) {
                                    Image(systemName: "doc.text.magnifyingglass")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("View session JSONL")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Resume Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button("New Session") {
                        chatManager.startNewConversation()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .task {
                isLoading = true
                sessions = await chatManager.listSessions()
                isLoading = false
            }
            .sheet(item: $selectedSessionForDetail) { session in
                ChatSessionDetailView(session: session)
                    .environment(chatManager)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
