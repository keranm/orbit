import SwiftUI
import SwiftData

/// Manages the state and streaming lifecycle for a single conversation.
@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Published state

    /// Messages sorted oldest-first for display.
    private(set) var sortedMessages: [Message] = []
    private(set) var isStreaming = false
    /// Plain-language error shown inline below the last message on stream failure.
    private(set) var streamError: String?

    /// Composer input text — bound to ComposerView.
    var inputText = ""

    var canSend: Bool {
        runtimeIsReady
        && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && !isStreaming
    }

    private var runtimeIsReady: Bool {
        if let state = appState {
            return state.runtimeStatus == .ready || state.runtimeStatus == .starting
        }
        return true  // mock path in tests
    }

    // MARK: - Dependencies

    let chat: Chat
    private let service: any ChatServiceProtocol
    private let modelContext: ModelContext
    private weak var appState: AppState?

    // MARK: - Private

    private var streamTask: Task<Void, Never>?

    // MARK: - Init

    init(
        chat: Chat,
        modelContext: ModelContext,
        appState: AppState?,
        service: (any ChatServiceProtocol)? = nil
    ) {
        self.chat = chat
        self.modelContext = modelContext
        self.appState = appState
        if let service {
            self.service = service
        } else if let appState {
            self.service = SDKChatService(appState.runtimeManager)
        } else {
            self.service = ChatService()
        }
        refreshMessages()
    }

    // MARK: - Auto-respond

    /// Called by ChatView.task — starts streaming if the conversation ends with an unanswered user message.
    func sendIfNeeded() async {
        guard let last = sortedMessages.last, last.role == "user", !isStreaming else { return }
        await streamResponse()
    }

    // MARK: - Send from composer

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend else { return }
        inputText = ""
        streamError = nil

        let userMsg = Message(role: "user", content: text)
        chat.messages.append(userMsg)
        chat.updatedAt = .now
        autoTitle(from: text)
        save()
        refreshMessages()

        await streamResponse()
    }

    // MARK: - Cancel

    func cancelStream() {
        streamTask?.cancel()
        streamTask = nil
        if let streaming = sortedMessages.last(where: { $0.isStreaming }) {
            streaming.isStreaming = false
            streaming.isInterrupted = streaming.content.isEmpty
            save()
            refreshMessages()
        }
        isStreaming = false
        appState?.novaState = .idle
    }

    // MARK: - Internal streaming

    private func waitForRuntimeReady() async {
        guard let state = appState else { return }
        var ticks = 0
        while state.runtimeStatus == .starting && ticks < 30 {
            try? await Task.sleep(for: .milliseconds(500))
            ticks += 1
        }
    }

    private func streamResponse() async {
        appState?.novaState = .thinking
        isStreaming = true
        streamError = nil

        // Placeholder message shown while waiting for first token
        let assistantMsg = Message(role: "assistant", content: "")
        assistantMsg.isStreaming = true
        chat.messages.append(assistantMsg)
        chat.updatedAt = .now
        save()
        refreshMessages()

        // If the user sent before the runtime finished starting, wait here.
        // The thinking placeholder is already visible so the UI looks live.
        await waitForRuntimeReady()

        guard appState?.runtimeStatus == .ready else {
            assistantMsg.isStreaming = false
            assistantMsg.isInterrupted = true
            save(); refreshMessages()
            isStreaming = false
            streamError = "Your AI isn't ready yet. Try again in a moment."
            appState?.novaState = .error
            return
        }

        // Resolve model ref — chat may have been created before the runtime was
        // ready, in which case chat.modelRef is empty. Use the live ref instead.
        let liveRef = appState?.activeModelRef ?? ""
        let modelRef: String
        if !liveRef.isEmpty {
            modelRef = liveRef
            if chat.modelRef.isEmpty { chat.modelRef = liveRef; save() }
        } else {
            modelRef = chat.modelRef
        }
        // Truncate to last 40 messages (20 exchanges) to stay within model context limits
        let history: [ChatRequestMessage] = sortedMessages
            .filter { !$0.isStreaming }
            .suffix(40)
            .map { ChatRequestMessage(role: $0.role, content: $0.content) }

        // Build system message from PromptSettings — includes default prompt,
        // user preferences, and optionally local context.
        let systemMessage = PromptSettings.buildSystemMessage()

        let sendTime = Date()
        var firstTokenTime: Date?

        streamTask = Task {
            do {
                let stream = service.streamCompletion(
                    messages: history,
                    model: modelRef,
                    systemPrompt: systemMessage
                )
                appState?.novaState = .responding

                for try await event in stream {
                    guard !Task.isCancelled else { break }

                    switch event {
                    case .token(let token):
                        if firstTokenTime == nil { firstTokenTime = Date() }
                        assistantMsg.content += token
                    case .done(let promptTokens, let completionTokens):
                        assistantMsg.tokenCount = completionTokens
                        assistantMsg.promptTokenCount = promptTokens
                        if let ft = firstTokenTime {
                            assistantMsg.inferenceLatency = ft.timeIntervalSince(sendTime)
                        }
                        assistantMsg.wasLocalInference = true
                    }
                }

                guard !Task.isCancelled else {
                    assistantMsg.isStreaming = false
                    assistantMsg.isInterrupted = true
                    save(); refreshMessages()
                    isStreaming = false
                    appState?.novaState = .idle
                    return
                }

                assistantMsg.isStreaming = false
                assistantMsg.isInterrupted = false
                chat.updatedAt = .now
                save()
                refreshMessages()

                isStreaming = false
                appState?.novaState = .success
                try? await Task.sleep(for: .seconds(2))
                if appState?.novaState == .success { appState?.novaState = .idle }

            } catch {
                assistantMsg.isStreaming = false
                assistantMsg.isInterrupted = assistantMsg.content.isEmpty
                save()
                refreshMessages()

                isStreaming = false
                streamError = userFacingError(error)
                appState?.novaState = .error
            }
        }
        await streamTask?.value
    }

    // MARK: - Helpers

    private func refreshMessages() {
        sortedMessages = chat.messages.sorted { $0.createdAt < $1.createdAt }
    }

    private func save() {
        try? modelContext.save()
    }

    private func autoTitle(from text: String) {
        guard chat.title == "New Chat" else { return }
        let capped = String(text.prefix(42))
        chat.title = capped.count < text.count ? "\(capped)…" : capped
    }

    private func userFacingError(_ error: Error) -> String {
        if let ce = error as? ChatError { return ce.errorDescription ?? "Response interrupted" }
        if let ue = error as? URLError, ue.code == .cancelled { return "" }
        let desc = error.localizedDescription
        if desc.isEmpty { return "Response interrupted" }
        return desc
    }
}
