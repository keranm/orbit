import Foundation
import Observation

@MainActor
@Observable
final class PlaygroundViewModel {
    let chatService: ChatService

    // Conversation
    var messages: [PlaygroundMessage] = []
    var systemPrompt: String = ""
    var currentInput: String = ""
    var isStreaming: Bool = false
    var modelRef: String = ""

    // Parameters
    var temperature: Double = 0.7
    var topP: Double = 0.95
    var maxTokens: Int = 4096
    var frequencyPenalty: Double = 0.0
    var presencePenalty: Double = 0.0

    // Metrics (per-run)
    var lastTokenCount: Int?
    var lastPromptTokenCount: Int?
    var lastLatency: TimeInterval?
    var lastWasLocal: Bool?

    /// Running history of latency and throughput across consecutive runs.
    var latencyHistory: [TimeInterval] = []
    var throughputHistory: [Double] = []

    init(chatService: ChatService = ChatService()) {
        self.chatService = chatService
    }

    func send() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMsg = PlaygroundMessage(role: "user", content: trimmed)
        messages.append(userMsg)
        currentInput = ""
        isStreaming = true

        resetMetrics()
        let startTime = CFAbsoluteTimeGetCurrent()
        let chatMessages = messages.map { ChatRequestMessage(role: $0.role, content: $0.content) }

        let stream = chatService.streamCompletion(
            messages: chatMessages,
            model: modelRef,
            systemPrompt: systemPrompt,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty
        )

        Task {
            var fullContent = ""
            do {
                for try await event in stream {
                    switch event {
                    case .token(let text):
                        fullContent += text
                        updateLastMessage(with: fullContent)
                    case .done(let promptTokens, let completionTokens):
                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        lastTokenCount = completionTokens
                        lastPromptTokenCount = promptTokens
                        lastLatency = elapsed
                        lastWasLocal = true
                        if let ct = completionTokens, ct > 0, elapsed > 0 {
                            latencyHistory.append(elapsed)
                            throughputHistory.append(Double(ct) / elapsed)
                        }
                        messages.append(PlaygroundMessage(role: "assistant", content: fullContent))
                        isStreaming = false
                    }
                }
            } catch {
                isStreaming = false
            }
        }
    }

    func stop() {
        isStreaming = false
    }

    func sendCompletion() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        messages.removeAll()
        currentInput = ""
        isStreaming = true

        resetMetrics()
        let startTime = CFAbsoluteTimeGetCurrent()
        let chatMessages = [ChatRequestMessage(role: "user", content: trimmed)]

        let stream = chatService.streamCompletion(
            messages: chatMessages,
            model: modelRef,
            systemPrompt: systemPrompt,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty
        )

        Task {
            var fullContent = ""
            do {
                for try await event in stream {
                    switch event {
                    case .token(let text):
                        fullContent += text
                        updateLastMessage(with: fullContent)
                    case .done(let promptTokens, let completionTokens):
                        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
                        lastTokenCount = completionTokens
                        lastPromptTokenCount = promptTokens
                        lastLatency = elapsed
                        lastWasLocal = true
                        if let ct = completionTokens, ct > 0, elapsed > 0 {
                            latencyHistory.append(elapsed)
                            throughputHistory.append(Double(ct) / elapsed)
                        }
                        messages.append(PlaygroundMessage(role: "assistant", content: fullContent))
                        isStreaming = false
                    }
                }
            } catch {
                isStreaming = false
            }
        }
    }

    func clear() {
        messages.removeAll()
        currentInput = ""
        resetMetrics()
    }

    private func resetMetrics() {
        lastTokenCount = nil
        lastPromptTokenCount = nil
        lastLatency = nil
        lastWasLocal = nil
        latencyHistory.removeAll()
        throughputHistory.removeAll()
    }

    private func updateLastMessage(with fullContent: String) {
        if messages.last?.role == "assistant" {
            messages[messages.count - 1].content = fullContent
        } else {
            messages.append(PlaygroundMessage(role: "assistant", content: fullContent))
        }
    }
}

struct PlaygroundMessage: Identifiable {
    let id = UUID()
    let role: String
    var content: String
}
