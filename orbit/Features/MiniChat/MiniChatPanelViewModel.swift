import Foundation
import SwiftUI
import SwiftData

/// Manages the state for Nova Mini-Chat.
///
/// Conversations are persisted into SwiftData so they appear automatically
/// in the main Orbit app sidebar. The view model holds a reference to the
/// active Chat and appends Messages in real time as tokens stream in.
@Observable
@MainActor
final class MiniChatPanelViewModel {

    // MARK: - Animation phase

    enum Phase: Equatable {
        case hidden
        case appearing       // Nova fades in
        case listening       // Input expands
        case conversing      // Conversation visible
        case dismissing      // Fading out
        case escalating      // Runtime unavailable → transitioning to main app
    }

    // MARK: - State

    var phase: Phase = .hidden
    var inputText = ""
    var isStreaming = false
    var streamError: String?

    /// The live SwiftData Chat being built by this session.
    private(set) var currentChat: Chat?

    /// All messages in the current session, newest last.
    var messages: [Message] { currentChat?.messages.sorted { $0.createdAt < $1.createdAt } ?? [] }

    var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isStreaming
    }

    var hasMessages: Bool { !(currentChat?.messages.isEmpty ?? true) }

    // MARK: - Dependencies

    private let service: any ChatServiceProtocol
    private var streamTask: Task<Void, Never>?
    private var activeModelRef: String?
    private var systemMessage: String = ""
    private var modelContext: ModelContext?

    // MARK: - Init

    init(service: (any ChatServiceProtocol)? = nil, apiPort: Int = 9337) {
        self.service = service ?? ChatService(apiPort: apiPort)
    }

    // MARK: - Configure

    /// Updates model ref, system message, and optionally the persistence context.
    /// Pass nil for modelContext to leave the existing context unchanged — used when
    /// re-syncing model/prompt on show() without disturbing the already-wired context.
    func configure(modelRef: String?, systemMessage: String, modelContext: ModelContext?) {
        self.activeModelRef = modelRef
        self.systemMessage = systemMessage
        if let context = modelContext {
            self.modelContext = context
        }
    }

    // MARK: - Send

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, canSend, let modelRef = activeModelRef else {
            // No model — escalate to main app
            withAnimation(.easeInOut(duration: 0.2)) { phase = .escalating }
            return
        }
        inputText = ""
        streamError = nil

        // First message in session: create a SwiftData Chat
        let chat = ensureChat(modelRef: modelRef)

        let userMsg = Message(role: "user", content: text)
        chat.messages.append(userMsg)
        chat.updatedAt = .now
        save()

        // Move to conversing phase if not already
        if phase != .conversing {
            withAnimation(.spring(duration: 0.35, bounce: 0.1)) { phase = .conversing }
        }

        // Placeholder assistant message
        let assistantMsg = Message(role: "assistant", content: "")
        assistantMsg.isStreaming = true
        chat.messages.append(assistantMsg)
        chat.updatedAt = .now
        save()

        isStreaming = true

        let history: [ChatRequestMessage] = messages
            .filter { !$0.isStreaming }
            .suffix(20)
            .map { ChatRequestMessage(role: $0.role, content: $0.content) }

        streamTask = Task {
            do {
                let stream = service.streamCompletion(
                    messages: history,
                    model: modelRef,
                    systemPrompt: systemMessage
                )
                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    assistantMsg.content += token
                }
                guard !Task.isCancelled else {
                    assistantMsg.isStreaming = false
                    assistantMsg.isInterrupted = true
                    save()
                    isStreaming = false
                    return
                }
                assistantMsg.isStreaming = false
                assistantMsg.isInterrupted = false
                chat.updatedAt = .now
                save()
                isStreaming = false
            } catch {
                assistantMsg.isStreaming = false
                assistantMsg.isInterrupted = true
                save()
                isStreaming = false
                let err = error as? ChatError
                streamError = err?.errorDescription ?? "Response interrupted"
            }
        }
        await streamTask?.value
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if let msg = currentChat?.messages.first(where: { $0.isStreaming }) {
            msg.isStreaming = false
            msg.isInterrupted = true
            save()
        }
        isStreaming = false
    }

    func clearSession() {
        cancel()
        currentChat = nil
        inputText = ""
        streamError = nil
    }

    // MARK: - Private helpers

    private func ensureChat(modelRef: String) -> Chat {
        if let existing = currentChat { return existing }
        let chat = Chat(modelRef: modelRef)
        chat.title = "Quick Chat"
        modelContext?.insert(chat)
        save()
        currentChat = chat
        return chat
    }

    private func save() {
        try? modelContext?.save()
    }
}
