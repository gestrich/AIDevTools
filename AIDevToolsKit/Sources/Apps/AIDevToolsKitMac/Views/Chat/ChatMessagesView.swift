import AIOutputSDK
import AppKit
import ChatFeature
import SwiftUI

// MARK: - Display Row

enum ChatDisplayRow: Identifiable {
    case messageHeader(ChatMessage)
    case block(messageId: UUID, offset: Int, block: AIContentBlock)
    case streamingIndicator(messageId: UUID)

    var id: String {
        switch self {
        case .messageHeader(let msg): return "\(msg.id)-header"
        case .block(let msgId, let offset, _): return "\(msgId)-block-\(offset)"
        case .streamingIndicator(let msgId): return "\(msgId)-streaming"
        }
    }
}

// MARK: - Chat Messages View

struct ChatMessagesView: View {
    @Environment(ChatModel.self) var chatModel: ChatModel
    @State private var isNearBottom: Bool = true
    @State private var lastSeenMessageId: UUID?
    @State private var scrollDebounceTask: Task<Void, Never>?
    @State private var showFullOutput: Bool = true
    @State private var collapsedMessageIds: Set<UUID> = []

    private var displayedMessages: [ChatMessage] {
        if showFullOutput {
            return chatModel.messages
        }
        if let last = chatModel.messages.last {
            return [last]
        }
        return []
    }

    private var allRows: [ChatDisplayRow] {
        displayedMessages.flatMap { message -> [ChatDisplayRow] in
            var rows: [ChatDisplayRow] = [.messageHeader(message)]

            let isCollapsed = collapsedMessageIds.contains(message.id)
            let hasText = message.contentBlocks.contains { if case .text = $0 { return true }; return false }

            for (i, block) in message.contentBlocks.enumerated() {
                if isCollapsed && hasText {
                    switch block {
                    case .thinking, .toolUse, .toolResult: continue
                    default: break
                    }
                }
                rows.append(.block(messageId: message.id, offset: i, block: block))
            }

            let isStreaming = message.role == .assistant
                && chatModel.isProcessing
                && chatModel.messages.last?.id == message.id
            if isStreaming && !message.contentBlocks.isEmpty {
                rows.append(.streamingIndicator(messageId: message.id))
            }

            return rows
        }
    }

    private static let latestModeTailLines = 30

    private var displayRows: [ChatDisplayRow] {
        if showFullOutput {
            return allRows
        }
        guard var last = allRows.last else { return [] }
        if case .block(let msgId, let offset, .text(let text)) = last {
            let lines = text.components(separatedBy: .newlines)
            if lines.count > Self.latestModeTailLines {
                let truncated = lines.suffix(Self.latestModeTailLines).joined(separator: "\n")
                last = .block(messageId: msgId, offset: offset, block: .text(truncated))
            }
        }
        return [last]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                List {
                    if chatModel.isLoadingHistory {
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
                    } else if chatModel.messages.isEmpty {
                        emptyStateView
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                    } else {
                        ForEach(displayRows) { row in
                            displayRowView(row)
                                .listRowSeparator(.hidden)
                                .listRowInsets(rowInsets(for: row))
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .onAppear {
                                isNearBottom = true
                                lastSeenMessageId = chatModel.messages.last?.id
                            }
                            .onDisappear {
                                isNearBottom = false
                            }
                    }
                }
                .listStyle(.plain)
                .defaultScrollAnchor(.bottom)
                .onAppear {
                    if !chatModel.messages.isEmpty {
                        Task {
                            try? await Task.sleep(for: .milliseconds(50))
                            await MainActor.run {
                                proxy.scrollTo("bottom", anchor: .bottom)
                            }
                        }
                    }
                }
                .onChange(of: chatModel.messages.count) { oldCount, newCount in
                    guard newCount > oldCount, isNearBottom else { return }
                    scrollDebounceTask?.cancel()
                    scrollDebounceTask = nil
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
                .onChange(of: chatModel.messages.last?.contentBlocks) { _, _ in
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

                VStack(spacing: 8) {
                    if !chatModel.messages.isEmpty {
                        HStack {
                            Spacer()
                            Button(action: { showFullOutput.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: showFullOutput ? "text.justify" : "text.line.last.and.arrowtriangle.forward")
                                        .font(.system(size: 11))
                                    Text(showFullOutput ? "Full" : "Latest")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(.ultraThinMaterial)
                                        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
                                )
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 12)
                            .padding(.top, 8)
                        }
                    }

                    if !chatModel.messages.isEmpty && !isNearBottom {
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
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.easeInOut(duration: 0.2), value: isNearBottom)
                    }
                }
            }
        }
    }

    // MARK: - Row Rendering

    @ViewBuilder
    private func displayRowView(_ row: ChatDisplayRow) -> some View {
        switch row {
        case .messageHeader(let message):
            ChatMessageHeaderRow(
                message: message,
                providerDisplayName: chatModel.providerDisplayName,
                isCollapsed: collapsedMessageIds.contains(message.id),
                onToggleCollapse: { toggleCollapse(for: message) }
            )
        case .block(_, _, let block):
            ChatBlockRow(block: block)
        case .streamingIndicator:
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.small)
                Text("Streaming...")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 44)
            .padding(.vertical, 4)
        }
    }

    private func rowInsets(for row: ChatDisplayRow) -> EdgeInsets {
        switch row {
        case .messageHeader:
            return EdgeInsets(top: 8, leading: 12, bottom: 2, trailing: 12)
        case .block, .streamingIndicator:
            return EdgeInsets(top: 1, leading: 12, bottom: 1, trailing: 12)
        }
    }

    private func toggleCollapse(for message: ChatMessage) {
        if collapsedMessageIds.contains(message.id) {
            collapsedMessageIds.remove(message.id)
        } else {
            collapsedMessageIds.insert(message.id)
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 60))
                .foregroundStyle(.blue)

            Text("\(chatModel.providerDisplayName) Chat")
                .font(.title)
                .fontWeight(.bold)

            VStack(spacing: 8) {
                Text("Chat with \(chatModel.providerDisplayName)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if chatModel.settings.resumeLastSession {
                    Label("Will resume last session on startup", systemImage: "arrow.triangle.branch")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if chatModel.settings.verboseMode {
                    Label("Thinking process will be shown", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.purple)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func calculateUnseenMessageCount() -> Int {
        guard let lastSeenId = lastSeenMessageId else { return 0 }
        guard let lastSeenIndex = chatModel.messages.firstIndex(where: { $0.id == lastSeenId }) else {
            return chatModel.messages.count
        }
        return max(0, chatModel.messages.count - lastSeenIndex - 1)
    }
}

// MARK: - Message Header Row

struct ChatMessageHeaderRow: View {
    let message: ChatMessage
    let providerDisplayName: String
    let isCollapsed: Bool
    let onToggleCollapse: () -> Void

    private var hasThinkingOrTools: Bool {
        message.contentBlocks.contains { block in
            switch block {
            case .thinking, .toolUse, .toolResult: return true
            default: return false
            }
        }
    }

    private var hasText: Bool {
        message.contentBlocks.contains { if case .text = $0 { return true }; return false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                        Text(message.role == .user ? "You" : providerDisplayName)
                            .font(.headline)
                        Spacer()
                        Text(message.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if message.contentBlocks.isEmpty && message.role == .assistant {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Thinking...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

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

                    if hasText && hasThinkingOrTools {
                        Button(action: onToggleCollapse) {
                            HStack(spacing: 4) {
                                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                                    .font(.caption)
                                Text(isCollapsed ? "Show thinking & tools" : "Hide thinking & tools")
                                    .font(.caption)
                            }
                            .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 4)
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 0, bottomTrailingRadius: 0, topTrailingRadius: 8)
                .fill(message.role == .user ? Color.blue.opacity(0.1) : Color.purple.opacity(0.1))
        )
    }
}

// MARK: - Block Row

struct ChatBlockRow: View {
    let block: AIContentBlock

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 36)
            blockContent
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private var blockContent: some View {
        switch block {
        case .thinking(let content):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundStyle(.purple)
                CollapsibleToolContent(text: content, previewLineCount: 6)
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
        case .toolUse(let name, let detail):
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "terminal")
                        .font(.caption2)
                    Text("[\(name)]")
                        .fontWeight(.medium)
                    Text(detail.components(separatedBy: .newlines).first ?? detail)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if detail.components(separatedBy: .newlines).count > 1 {
                    CollapsibleToolContent(text: detail, previewLineCount: 1)
                        .padding(.leading, 20)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.1))
            )
        case .toolResult(_, let summary, let isError):
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: isError ? "xmark.circle" : "checkmark.circle")
                    .font(.caption2)
                    .foregroundStyle(isError ? .red : .green)
                CollapsibleToolContent(text: summary, previewLineCount: 4)
            }
            .padding(.leading, 16)
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

// MARK: - Collapsible Tool Content

struct CollapsibleToolContent: View {
    let text: String
    let previewLineCount: Int
    @State private var isExpanded = false

    private var lines: [String] {
        text.components(separatedBy: .newlines)
    }

    private var needsCollapsing: Bool {
        lines.count > previewLineCount
    }

    var body: some View {
        if needsCollapsing {
            VStack(alignment: .leading, spacing: 4) {
                Text(isExpanded ? text : lines.prefix(previewLineCount).joined(separator: "\n"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button(action: { isExpanded.toggle() }) {
                    Text(isExpanded ? "Show less" : "+\(lines.count - previewLineCount) lines (click to expand)")
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.plain)
            }
        } else {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
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
