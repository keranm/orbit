import SwiftUI
import SwiftData

/// Full conversation view — message list + composer for follow-up messages.
struct ChatView: View {
    let chat: Chat

    @Environment(AppState.self) private var appState
    @Environment(\.modelContext) private var modelContext

    @State private var viewModel: ChatViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                chatContent(vm: vm)
            } else {
                Color.oBackground
            }
        }
        .onAppear { ensureViewModel() }
        .task { await viewModel?.sendIfNeeded() }
    }

    // MARK: - Content

    private func chatContent(vm: ChatViewModel) -> some View {
        VStack(spacing: 0) {
            messageList(vm: vm)
            Divider()
            ComposerView(
                text: Binding(get: { vm.inputText }, set: { vm.inputText = $0 }),
                isStreaming: vm.isStreaming,
                canSend: vm.canSend,
                onSend: { Task { await vm.send() } },
                onCancel: { vm.cancelStream() }
            )
            .padding(.horizontal, OSpacing.xl)
            .padding(.vertical, OSpacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.oBackground)
    }

    // MARK: - Message list

    private func messageList(vm: ChatViewModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: OSpacing.md) {
                    // Top padding — Nova companion overlay sits here
                    Color.clear.frame(height: OSpacing.xxl)

                    ForEach(vm.sortedMessages, id: \.id) { message in
                        MessageBubble(message: message)
                            .padding(.horizontal, OSpacing.xl)
                            .id(message.id)
                    }

                    if let err = vm.streamError, !err.isEmpty {
                        streamErrorBanner(err)
                            .padding(.horizontal, OSpacing.xl)
                    }

                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.bottom, OSpacing.md)
            }
            .mask(scrollFadeMask)
            .onChange(of: vm.sortedMessages.count) { scrollToBottom(proxy: proxy) }
            .onChange(of: vm.isStreaming) { _, streaming in
                if streaming { scrollToBottom(proxy: proxy) }
            }
        }
    }

    /// Gradient that fades messages as they scroll beneath the Nova overlay area.
    private var scrollFadeMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear,  location: 0.00),
                .init(color: .black,  location: 0.07),
                .init(color: .black,  location: 1.00),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func streamErrorBanner(_ message: String) -> some View {
        HStack(spacing: OSpacing.sm) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 13))
                .foregroundStyle(Color.oWarningAmber)
            Text(message)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
            Spacer()
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: ORadius.md)
                        .stroke(Color.oWarningAmber.opacity(0.3), lineWidth: 1.5)
                )
        )
    }

    // MARK: - ViewModel lifecycle

    private func ensureViewModel() {
        guard viewModel == nil else { return }
        viewModel = ChatViewModel(chat: chat, modelContext: modelContext, appState: appState)
    }
}

// MARK: - Loader (fetches Chat by ID from SwiftData)

/// Thin wrapper used by MainWindowView to look up a chat by ID before presenting ChatView.
struct ChatViewLoader: View {
    let chatID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(AppState.self) private var appState

    var body: some View {
        if let chat = fetchChat() {
            ChatView(chat: chat)
        } else {
            VStack(spacing: OSpacing.md) {
                Spacer()
                Text("Chat not found")
                    .font(.oBody)
                    .foregroundStyle(Color.oTextSecondary)
                Button("New Chat") { appState.route = .newChat }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.oAccent)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.oBackground)
        }
    }

    private func fetchChat() -> Chat? {
        let id = chatID
        let descriptor = FetchDescriptor<Chat>(predicate: #Predicate { $0.id == id })
        return try? modelContext.fetch(descriptor).first
    }
}
