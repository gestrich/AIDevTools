import SwiftUI

struct ChatSettingsView: View {
    @Environment(MCPModel.self) private var mcpModel: MCPModel
    @Environment(SettingsModel.self) private var settingsModel
    @State private var chatSettings = ChatSettings()

    var body: some View {
        Form {
            Section {
                Toggle("Enable Streaming", isOn: Binding(
                    get: { chatSettings.enableStreaming },
                    set: { chatSettings.enableStreaming = $0 }
                ))
                .help("Show response as it's being generated")

                Toggle("Resume Last Session", isOn: Binding(
                    get: { chatSettings.resumeLastSession },
                    set: { chatSettings.resumeLastSession = $0 }
                ))
                .help("Automatically resume the most recent session when the app starts")
            } header: {
                Text("Conversation")
            }

            Section {
                Toggle("Verbose Mode", isOn: Binding(
                    get: { chatSettings.verboseMode },
                    set: { chatSettings.verboseMode = $0 }
                ))
                .help("Show thinking process and intermediate steps")

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
                .help("Maximum tokens for thinking output (minimum: 1024)")
            } header: {
                Text("Thinking & Reasoning")
            } footer: {
                Text("Verbose mode shows internal reasoning. Thinking tokens must be at least 1024.")
            }

            Section {
                LabeledContent("AIDevTools Repo Path") {
                    HStack {
                        if let repoPath = settingsModel.aiDevToolsRepoPath {
                            Text(repoPath.path(percentEncoded: false))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Not set")
                                .foregroundStyle(.tertiary)
                        }
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseFiles = false
                            panel.canChooseDirectories = true
                            panel.allowsMultipleSelection = false
                            if let repoPath = settingsModel.aiDevToolsRepoPath {
                                panel.directoryURL = repoPath
                            }
                            if panel.runModal() == .OK, let url = panel.url {
                                settingsModel.updateAIDevToolsRepoPath(url)
                            }
                        }
                        if settingsModel.aiDevToolsRepoPath != nil {
                            Button("Clear") {
                                settingsModel.updateAIDevToolsRepoPath(nil)
                            }
                        }
                    }
                }

                switch mcpModel.status {
                case .notConfigured:
                    LabeledContent("Status") {
                        Text("Not configured — set repo path above")
                            .foregroundStyle(.secondary)
                    }
                case .binaryMissing:
                    LabeledContent("Status") {
                        Text("Binary not found. Build the app in Xcode or run `swift build --target AIDevToolsKitCLI`.")
                            .foregroundStyle(.orange)
                    }
                case let .ready(binaryURL, builtAt):
                    LabeledContent("Binary") {
                        Text(binaryURL.path(percentEncoded: false))
                            .foregroundStyle(.secondary)
                            .fontDesign(.monospaced)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                    LabeledContent("Last Built") {
                        Text(builtAt, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("MCP")
            } footer: {
                Text("The MCP server lets Claude access live app state during chat. Set the AIDevTools repo path so the app can find the CLI binary.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
