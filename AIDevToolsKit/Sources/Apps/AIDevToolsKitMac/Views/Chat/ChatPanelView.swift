import AIOutputSDK
import AppKit
import ChatFeature
import SwiftUI

struct ChatPanelView: View {
    @Environment(ChatModel.self) private var chatModel: ChatModel
    @State private var messageText: String = ""
    @State private var pastedImages: [ImageAttachment] = []
    @State private var showingQueueViewer: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ChatMessagesView()

            Divider()

            messageInputView
        }
        .sheet(isPresented: $showingQueueViewer) {
            ChatQueueViewerSheet()
        }
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
                    workingDirectory: chatModel.workingDirectory,
                    onSubmit: sendMessage
                )

                if !chatModel.messageQueue.isEmpty {
                    Button(action: { showingQueueViewer = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "tray.full")
                                .font(.title3)
                                .foregroundStyle(.orange)

                            Text("\(chatModel.messageQueue.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Circle().fill(.orange))
                                .offset(x: 8, y: -8)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("View queued messages (\(chatModel.messageQueue.count))")
                }

                if chatModel.isProcessing {
                    Button(action: { chatModel.cancelCurrentRequest() }) {
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
            await chatModel.sendMessage(message, images: images)
        }
    }

}

// MARK: - Message Row

struct ChatMessageRow: View {
    let message: ChatMessage
    @Environment(ChatModel.self) private var chatModel: ChatModel?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if message.role == .user {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            } else {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.role == .user ? "You" : (chatModel?.providerDisplayName ?? "Assistant"))
                        .font(.headline)
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let isCurrentlyStreaming = message.role == .assistant &&
                    (chatModel?.isProcessing ?? false) &&
                    chatModel?.messages.last?.id == message.id

                if message.contentBlocks.isEmpty && message.role == .assistant {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Thinking...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        if !message.images.isEmpty {
                            ForEach(message.images) { imageAttachment in
                                if let nsImage = imageAttachment.toNSImage() {
                                    Image(nsImage: nsImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(maxWidth: 300)
                                        .cornerRadius(8)
                                }
                            }
                        }

                        if !message.contentBlocks.isEmpty {
                            ChatFormattedContent(message: message, isProcessing: chatModel?.isProcessing ?? false)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if isCurrentlyStreaming {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Streaming...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.top, 4)
                        }
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(message.role == .user ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
        )
    }
}

// MARK: - Formatted Content

struct ChatFormattedContent: View {
    let message: ChatMessage
    let isProcessing: Bool
    @State private var showThinkingAndTools = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let blocks = message.contentBlocks
            let hasText = blocks.contains { if case .text = $0 { return true }; return false }
            let hasThinkingOrTools = blocks.contains { block in
                switch block {
                case .thinking, .toolUse, .toolResult: return true
                default: return false
                }
            }

            if hasText && hasThinkingOrTools {
                Button(action: { showThinkingAndTools.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: showThinkingAndTools ? "chevron.down" : "chevron.right")
                            .font(.caption)
                        Text(showThinkingAndTools ? "Hide thinking & tools" : "Show thinking & tools")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.bottom, 4)
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .thinking(let content):
                    if showThinkingAndTools || !hasText {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "brain")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text(content)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.purple.opacity(0.08))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
                        )
                    }
                case .toolUse(let name, let detail):
                    if showThinkingAndTools || !hasText {
                        HStack(spacing: 6) {
                            Image(systemName: "terminal")
                                .font(.caption2)
                            Text("[\(name)]")
                                .fontWeight(.medium)
                            Text(detail)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.1))
                        )
                    }
                case .toolResult(_, let summary, let isError):
                    if showThinkingAndTools || !hasText {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: isError ? "xmark.circle" : "checkmark.circle")
                                .font(.caption2)
                                .foregroundStyle(isError ? .red : .green)
                            Text(summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 16)
                    }
                case .metrics(let duration, let cost, let turns):
                    HStack(spacing: 12) {
                        if let duration {
                            Text(String(format: "%.1fs", duration))
                        }
                        if let cost {
                            Text(String(format: "$%.4f", cost))
                        }
                        if let turns {
                            Text("\(turns) turns")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                case .text(let text):
                    Text(text)
                        .font(.body)
                }
            }
        }
        .onAppear {
            showThinkingAndTools = !message.shouldCollapseThinking
        }
        .onChange(of: message.isComplete) { _, isComplete in
            if isComplete && message.shouldCollapseThinking {
                showThinkingAndTools = false
            }
        }
    }
}

// MARK: - ImageAttachment NSImage Conversion

extension ImageAttachment {
    func toNSImage() -> NSImage? {
        guard let data = Data(base64Encoded: base64Data) else { return nil }
        return NSImage(data: data)
    }
}
