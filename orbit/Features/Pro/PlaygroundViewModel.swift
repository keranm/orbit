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

    var currentRun: RunMetrics?
    var runHistory: [RunMetrics] = []

    private var streamTask: Task<Void, Never>?

    init(chatService: ChatService? = nil) {
        self.chatService = chatService ?? ChatService()
    }

    func send() {
        let trimmed = currentInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreaming else { return }

        let userMsg = PlaygroundMessage(role: "user", content: trimmed)
        messages.append(userMsg)
        currentInput = ""
        isStreaming = true
        resetMetrics()

        let startedAt = Date()
        let startTime = CFAbsoluteTimeGetCurrent()
        let chatMessages = messages.map { ChatRequestMessage(role: $0.role, content: $0.content) }
        let usedModel = modelRef

        let stream = chatService.streamCompletion(
            messages: chatMessages,
            model: usedModel,
            systemPrompt: systemPrompt,
            temperature: temperature,
            topP: topP,
            maxTokens: maxTokens,
            frequencyPenalty: frequencyPenalty,
            presencePenalty: presencePenalty
        )

        streamTask = Task {
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
                        let metrics = RunMetrics(
                            modelRef: usedModel,
                            startedAt: startedAt,
                            durationSeconds: elapsed,
                            promptTokens: promptTokens ?? 0,
                            completionTokens: completionTokens ?? 0,
                            avgTokensPerSecond: elapsed > 0 ? Double(completionTokens ?? 0) / elapsed : 0,
                            wasLocal: true
                        )
                        currentRun = metrics
                        runHistory.append(metrics)
                        if runHistory.count > 10 { runHistory.removeFirst() }
                        isStreaming = false
                    }
                }
            } catch {
                isStreaming = false
            }
            streamTask = nil
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clear() {
        streamTask?.cancel()
        streamTask = nil
        messages.removeAll()
        currentInput = ""
        resetMetrics()
        currentRun = nil
    }

    func resetParameters() {
        temperature = 0.7
        topP = 0.95
        maxTokens = 4096
        frequencyPenalty = 0.0
        presencePenalty = 0.0
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

struct RunMetrics: Identifiable {
    let id = UUID()
    let modelRef: String
    let startedAt: Date
    let durationSeconds: Double
    let promptTokens: Int
    let completionTokens: Int
    let avgTokensPerSecond: Double
    let wasLocal: Bool
}
