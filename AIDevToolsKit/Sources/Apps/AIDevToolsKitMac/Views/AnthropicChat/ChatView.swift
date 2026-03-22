import SwiftUI

struct ChatView: View {
    @Bindable var viewModel: ChatViewModel
    @State private var inputText = ""
    @State private var useStreaming = true

    var body: some View {
        VStack(spacing: 0) {
            messagesSection
            errorSection
            Divider()
            inputSection
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Messages

    @ViewBuilder
    private var messagesSection: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    messagesList
                    streamingMessageView
                    loadingIndicator
                }
                .padding()
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation {
                    if let lastMessage = viewModel.messages.last {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingMessage) { _, _ in
                withAnimation {
                    if viewModel.isStreaming {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var messagesList: some View {
        ForEach(viewModel.messages) { message in
            MessageBubbleView(
                content: message.content,
                isUser: message.isUser,
                timestamp: message.timestamp
            )
            .id(message.id)
        }
    }

    @ViewBuilder
    private var streamingMessageView: some View {
        if viewModel.isStreaming && !viewModel.streamingMessage.isEmpty {
            MessageBubbleView(
                content: viewModel.streamingMessage,
                isUser: false,
                timestamp: Date()
            )
            .id("streaming")
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if viewModel.isLoading && !viewModel.isStreaming {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("AI is thinking...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Error

    @ViewBuilder
    private var errorSection: some View {
        if let error = viewModel.errorMessage {
            Text(error)
                .font(.caption)
                .foregroundColor(.red)
                .padding(.horizontal)
                .padding(.vertical, 4)
        }
    }

    // MARK: - Input

    @ViewBuilder
    private var inputSection: some View {
        HStack(spacing: 8) {
            TextField("Message Claude...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
                .lineLimit(1...5)
                .onSubmit {
                    sendMessage()
                }

            streamingToggle

            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
        }
        .padding()
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var streamingToggle: some View {
        Toggle(isOn: $useStreaming) {
            Image(systemName: useStreaming ? "bolt.fill" : "bolt.slash")
        }
        .toggleStyle(.button)
        .help(useStreaming ? "Streaming enabled" : "Streaming disabled")
    }

    // MARK: - Actions

    private func sendMessage() {
        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        inputText = ""

        Task {
            if useStreaming {
                await viewModel.streamMessage(message)
            } else {
                await viewModel.sendMessage(message)
            }
        }
    }
}
