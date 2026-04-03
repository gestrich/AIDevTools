import AIOutputSDK
import AppKit
import DataPathsService
import ProviderRegistryService
import SwiftUI

/// Full-height chat panel for the inspector sidebar.
///
/// Owns a `ChatModel` built from the context's system prompt.
/// The MCP config is written once at app startup (CompositionRoot) and referenced here by path.
struct ContextualChatPanel: View {
    let context: any ViewChatContext

    @Environment(ProviderModel.self) private var providerModel
    @State private var selectedProviderName: String = ""
    @State private var chatModel: ChatModel?
    @State private var messageText: String = ""
    @State private var pastedImages: [ImageAttachment] = []
    @State private var showingQueueViewer: Bool = false
    @State private var showingSessionPicker: Bool = false
    @State private var showingSettings: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            if let model = chatModel {
                Divider()
                ChatMessagesView()
                    .environment(model)
                    .frame(maxHeight: .infinity)
                Divider()
                messageInputView
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
        .sheet(isPresented: $showingQueueViewer) {
            if let model = chatModel {
                ChatQueueViewerSheet()
                    .environment(model)
            }
        }
        .sheet(isPresented: $showingSettings) {
            if let model = chatModel {
                ChatSettingsView()
                    .environment(model)
            }
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

            Button(action: { showingSessionPicker = true }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Session history")
            .popover(isPresented: $showingSessionPicker) {
                if let model = chatModel {
                    ChatSessionPickerView()
                        .environment(model)
                }
            }

            Button(action: { showingSettings = true }) {
                Image(systemName: "gear")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Chat settings")

            Button(action: { chatModel?.startNewConversation() }) {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("New conversation")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Message Input

    private var messageInputView: some View {
        VStack(spacing: 0) {
            if !pastedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(pastedImages) { imageAttachment in
                            if let nsImage = imageAttachment.toNSImage() {
                                ZStack(alignment: .topTrailing) {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(height: 80)
                                        .cornerRadius(4)

                                    Button(action: {
                                        pastedImages.removeAll { $0.id == imageAttachment.id }
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .gray)
                                            .font(.title3)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

                Divider()
            }

            if let model = chatModel {
                HStack(spacing: 12) {
                    Button(action: pasteImageFromClipboard) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Paste image from clipboard")

                    MessageInputWithAutocomplete(
                        messageText: $messageText,
                        workingDirectory: model.workingDirectory,
                        onSubmit: sendMessage
                    )

                    if !model.messageQueue.isEmpty {
                        Button(action: { showingQueueViewer = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "tray.full")
                                    .font(.title3)
                                    .foregroundStyle(.orange)

                                Text("\(model.messageQueue.count)")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Circle().fill(.orange))
                                    .offset(x: 8, y: -8)
                            }
                        }
                        .buttonStyle(.plain)
                        .help("View queued messages (\(model.messageQueue.count))")
                    }

                    if model.isProcessing {
                        Button(action: { model.cancelCurrentRequest() }) {
                            Image(systemName: "stop.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Stop generation")
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.title2)
                                .foregroundStyle((messageText.isEmpty && pastedImages.isEmpty) ? .gray : .blue)
                        }
                        .buttonStyle(.plain)
                        .disabled(messageText.isEmpty && pastedImages.isEmpty)
                        .help("Send message")
                    }
                }
                .padding()
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Actions

    private func pasteImageFromClipboard() {
        let pasteboard = NSPasteboard.general
        guard let image = NSImage(pasteboard: pasteboard) else { return }
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let base64 = pngData.base64EncodedString()
        let attachment = ImageAttachment(base64Data: base64, mediaType: "image/png")
        pastedImages.append(attachment)
    }

    private func sendMessage() {
        guard !messageText.isEmpty || !pastedImages.isEmpty else { return }

        let message = messageText
        let images = pastedImages
        messageText = ""
        pastedImages = []

        Task {
            await chatModel?.sendMessage(message, images: images)
        }
    }

    // MARK: - Private

    private func rebuildChatModel() {
        guard let client = providerModel.providerRegistry.client(named: selectedProviderName)
                ?? providerModel.providerRegistry.defaultClient else { return }

        let settings = ChatSettings()
        settings.resumeLastSession = false

        chatModel = ChatModel(configuration: ChatModelConfiguration(
            client: client,
            mcpConfigPath: DataPathsService.mcpConfigFileURL.path,
            settings: settings,
            systemPrompt: context.chatSystemPrompt,
            workingDirectory: context.chatWorkingDirectory
        ))
    }
}
