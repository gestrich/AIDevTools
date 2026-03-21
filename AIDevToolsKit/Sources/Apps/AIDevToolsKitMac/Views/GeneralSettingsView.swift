import ClaudeCodeChatService
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(SettingsModel.self) private var settingsModel
    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @State private var claudeCodeSettings = ClaudeCodeChatSettings()

    var body: some View {
        Form {
            Section("Anthropic API") {
                SecureField("API Key", text: $apiKey)
                Text("Required for the API chat mode. Get a key at console.anthropic.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Claude Code CLI") {
                Toggle("Enable Streaming", isOn: Binding(
                    get: { claudeCodeSettings.enableStreaming },
                    set: { claudeCodeSettings.enableStreaming = $0 }
                ))

                Toggle("Resume Last Session", isOn: Binding(
                    get: { claudeCodeSettings.resumeLastSession },
                    set: { claudeCodeSettings.resumeLastSession = $0 }
                ))

                Toggle("Verbose Mode", isOn: Binding(
                    get: { claudeCodeSettings.verboseMode },
                    set: { claudeCodeSettings.verboseMode = $0 }
                ))

                HStack {
                    Text("Max Thinking Tokens")
                    Spacer()
                    TextField("Tokens", value: Binding(
                        get: { claudeCodeSettings.maxThinkingTokens },
                        set: { claudeCodeSettings.maxThinkingTokens = max($0, 1024) }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                }

                Text("Settings for Claude Code CLI chat mode. Requires the claude CLI installed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Data Storage") {
                LabeledContent("Data Directory") {
                    HStack {
                        Text(settingsModel.dataPath.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                settingsModel.updateDataPath(url)
                            }
                        } label: {
                            Image(systemName: "folder")
                        }
                    }
                }

                Text("Directory where repository configurations and eval output are stored.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
