import ChatManagerService
import SwiftUI

struct GeneralSettingsView: View {
    @Environment(ProviderModel.self) private var providerModel
    @Environment(SettingsModel.self) private var settingsModel
    @AppStorage("anthropicAPIKey") private var apiKey = ""
    @State private var chatSettings = ChatSettings()

    var body: some View {
        Form {
            Section("Anthropic API") {
                SecureField("API Key", text: $apiKey)
                    .onChange(of: apiKey) { _, _ in
                        providerModel.refreshProviders()
                    }
                Text("Required for the API chat mode. Get a key at console.anthropic.com")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Chat Settings") {
                Toggle("Enable Streaming", isOn: Binding(
                    get: { chatSettings.enableStreaming },
                    set: { chatSettings.enableStreaming = $0 }
                ))

                Toggle("Resume Last Session", isOn: Binding(
                    get: { chatSettings.resumeLastSession },
                    set: { chatSettings.resumeLastSession = $0 }
                ))

                Toggle("Verbose Mode", isOn: Binding(
                    get: { chatSettings.verboseMode },
                    set: { chatSettings.verboseMode = $0 }
                ))

                HStack {
                    Text("Max Thinking Tokens")
                    Spacer()
                    TextField("Tokens", value: Binding(
                        get: { chatSettings.maxThinkingTokens },
                        set: { chatSettings.maxThinkingTokens = max($0, 1024) }
                    ), format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 100)
                }

                Text("Settings for chat mode. These apply to all providers.")
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
