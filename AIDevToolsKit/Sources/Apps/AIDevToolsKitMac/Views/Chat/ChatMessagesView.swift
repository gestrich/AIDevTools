import AppKit
import ChatFeature
import SwiftUI

struct ChatMessagesView: View {
    @Environment(ChatModel.self) var chatModel: ChatModel
    @State private var isNearBottom: Bool = true
    @State private var lastSeenMessageId: UUID?
    @State private var scrollDebounceTask: Task<Void, Never>?

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
                        ForEach(chatModel.messages) { message in
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
