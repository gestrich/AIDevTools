import ChatFeature
import ProviderRegistryService
import SwiftUI

/// A collapsible chat panel that is aware of the current view's context.
///
/// Owns a `ChatModel` built from the context's system prompt and response router.
/// The system prompt is stable — set once at chat model creation, not rebuilt per message.
struct ContextualChatPanel: View {
    let context: any ViewChatContext

    @Environment(ProviderModel.self) private var providerModel
    @AppStorage("contextualChatVisible") private var isVisible = true
    @State private var selectedProviderName: String = ""
    @State private var chatModel: ChatModel?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if isVisible, let model = chatModel {
                Divider()
                ChatPanelView()
                    .environment(model)
            }
        }
        .task(id: context.chatContextIdentifier) {
            if selectedProviderName.isEmpty {
                selectedProviderName = providerModel.providerRegistry.defaultClient?.name ?? ""
            }
            rebuildChatModel()
        }
        .onChange(of: selectedProviderName) {
            rebuildChatModel()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Chat")
                .font(.caption.weight(.medium))

            Spacer()

            Picker("", selection: $selectedProviderName) {
                ForEach(providerModel.providerRegistry.providers, id: \.name) { provider in
                    Text(provider.displayName).tag(provider.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 100)

            Button(action: { chatModel?.startNewConversation() }) {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New conversation")

            Button(action: { isVisible.toggle() }) {
                Image(systemName: isVisible ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(isVisible ? "Collapse chat" : "Expand chat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Private

    private func rebuildChatModel() {
        guard let client = providerModel.providerRegistry.client(named: selectedProviderName)
                ?? providerModel.providerRegistry.defaultClient else { return }

        let settings = ChatSettings()
        settings.resumeLastSession = false

        chatModel = ChatModel(configuration: ChatModelConfiguration(
            client: client,
            responseHandler: context.responseRouter,
            settings: settings,
            systemPrompt: SystemPromptBuilder().build(for: context),
            workingDirectory: context.chatWorkingDirectory
        ))
    }
}
