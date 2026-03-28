import AIOutputSDK
import AppKit
import ChatManagerService
import SwiftUI

struct ChatPanelView: View {
    @Environment(ChatManager.self) private var chatManager: ChatManager
    @State private var messageText: String = ""
    @State private var pastedImages: [ImageAttachment] = []
    @State private var showingQueueViewer: Bool = false
    @State private var isNearBottom: Bool = true
    @State private var lastSeenMessageId: UUID?
    @State private var scrollDebounceTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            chatMessagesView

            Divider()

            messageInputView
        }
        .sheet(isPresented: $showingQueueViewer) {
            ChatQueueViewerSheet()
        }
    }

    // MARK: - Chat Messages

    private var chatMessagesView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                List {
                    if chatManager.isLoadingHistory {
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Loading conversation...")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    } else if chatManager.messages.isEmpty {
                        emptyStateView
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(chatManager.messages) { message in
                            ChatMessageRow(message: message)
                                .id(message.id)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .onAppear {
                                isNearBottom = true
                                lastSeenMessageId = chatManager.messages.last?.id
                            }
                            .onDisappear {
                                isNearBottom = false
                            }
                    }
                }
                .listStyle(.plain)
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    if !chatManager.messages.isEmpty {
                        Task {
                            try? await Task.sleep(for: .milliseconds(50))
                            await MainActor.run {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: chatManager.messages.count) { oldCount, newCount in
                    guard newCount > oldCount, isNearBottom else { return }
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = nil
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: chatManager.messages.last?.content) { _, _ in
                    guard isNearBottom else { return }
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = Task {
                        try? await Task.sleep(for: .milliseconds(100))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                }
                .onDisappear {
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = nil
                }

                if !chatManager.messages.isEmpty && !isNearBottom {
                    Button(action: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 12, weight: .semibold))

                            let unseenCount = calculateUnseenMessageCount()
                            if unseenCount > 0 {
                                Text("\(unseenCount)")
                                    .font(.system(size: 12, weight: .bold))
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(Color.blue)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        )
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: isNearBottom)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("\(chatManager.providerDisplayName) Chat")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text("Chat with \(chatManager.providerDisplayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if chatManager.supportsSessionHistory && chatManager.settings.resumeLastSession {
                    Label("Will resume last session on startup", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if chatManager.settings.verboseMode {
                    Label("Thinking process will be shown", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
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
                    workingDirectory: chatManager.workingDirectory,
                    onSubmit: sendMessage
                )

                if !chatManager.messageQueue.isEmpty {
                    Button(action: { showingQueueViewer = true }) {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "tray.full")
                                .font(.title3)
                                .foregroundStyle(.orange)

                            Text("\(chatManager.messageQueue.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Circle().fill(.orange))
                                .offset(x: 8, y: -8)
                        }
                    }
                    .buttonStyle(.plain)
                    .help("View queued messages (\(chatManager.messageQueue.count))")
                }

                if chatManager.isProcessing {
                    Button(action: { chatManager.cancelCurrentRequest() }) {
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
            await chatManager.sendMessage(message, images: images)
        }
    }

    private func calculateUnseenMessageCount() -> Int {
        guard let lastSeenId = lastSeenMessageId else { return 0 }
        guard let lastSeenIndex = chatManager.messages.firstIndex(where: { $0.id == lastSeenId }) else {
            return chatManager.messages.count
        }
        return max(0, chatManager.messages.count - lastSeenIndex - 1)
    }
}

// MARK: - Message Row

struct ChatMessageRow: View {
    let message: ChatMessage
    @Environment(ChatManager.self) private var chatManager: ChatManager?

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
                    Text(message.role == .user ? "You" : (chatManager?.providerDisplayName ?? "Assistant"))
                        .font(.headline)
                    Spacer()
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let isCurrentlyStreaming = message.role == .assistant &&
                    (chatManager?.isProcessing ?? false) &&
                    chatManager?.messages.last?.id == message.id

                if message.content.isEmpty && message.role == .assistant {
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

                        if !message.content.isEmpty {
                            ChatFormattedContent(message: message, isProcessing: chatManager?.isProcessing ?? false)
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
            let lines = message.contentLines
            let hasText = lines.contains { $0.type == .text }

            if hasText && lines.contains(where: { $0.type == .thinking || $0.type == .tool }) {
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

            ForEach(lines, id: \.id) { line in
                switch line.type {
                case .thinking:
                    if showThinkingAndTools || !hasText {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "brain")
                                .font(.caption)
                                .foregroundStyle(.purple)
                            Text(line.text)
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
                case .tool:
                    if showThinkingAndTools || !hasText {
                        Text(line.text)
                            .font(.caption)
                            .italic()
                            .foregroundStyle(.secondary)
                    }
                case .text:
                    Text(line.text)
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
