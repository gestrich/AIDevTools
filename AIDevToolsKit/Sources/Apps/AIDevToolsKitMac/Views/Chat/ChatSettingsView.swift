import ChatManagerService
import SwiftUI

struct ChatSettingsView: View {
    @Environment(ChatManager.self) private var chatManager: ChatManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Streaming", isOn: Binding(
                        get: { chatManager.settings.enableStreaming },
                        set: { chatManager.settings.enableStreaming = $0 }
                    ))
                    .help("Show response as it's being generated")

                    Toggle("Resume Last Session", isOn: Binding(
                        get: { chatManager.settings.resumeLastSession },
                        set: { chatManager.settings.resumeLastSession = $0 }
                    ))
                    .help("Automatically resume the most recent session when the app starts")
                } header: {
                    Text("Conversation")
                }

                Section {
                    Toggle("Verbose Mode", isOn: Binding(
                        get: { chatManager.settings.verboseMode },
                        set: { chatManager.settings.verboseMode = $0 }
                    ))
                    .help("Show thinking process and intermediate steps")

                    HStack {
                        Text("Max Thinking Tokens")
                        Spacer()
                        TextField("Tokens", value: Binding(
                            get: { chatManager.settings.maxThinkingTokens },
                            set: { chatManager.settings.maxThinkingTokens = max($0, 1024) }
                        ), format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                    }
                    .help("Maximum tokens for thinking output (minimum: 1024)")
                } header: {
                    Text("Thinking & Reasoning")
                } footer: {
                    Text("Verbose mode shows internal reasoning. Thinking tokens must be at least 1024.")
                }

                Section {
                    LabeledContent("Working Directory") {
                        Text(chatManager.workingDirectory)
                            .font(.caption)
                            .fontDesign(.monospaced)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    LabeledContent("Provider") {
                        Text(chatManager.providerDisplayName)
                            .font(.caption)
                    }
                } header: {
                    Text("Context")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Chat Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}
