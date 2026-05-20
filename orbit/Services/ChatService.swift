import Foundation

// MARK: - Request / response types

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let stream: Bool = true

    enum CodingKeys: String, CodingKey {
        case model, messages, stream
    }
}

struct ChatRequestMessage: Encodable {
    let role: String
    let content: String
}

/// A single SSE chunk from the streaming completions endpoint.
struct ChatCompletionChunk: Decodable {
    let choices: [ChunkChoice]

    struct ChunkChoice: Decodable {
        let delta: ChunkDelta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
        }
    }

    struct ChunkDelta: Decodable {
        let role: String?
        let content: String?
    }
}

// MARK: - Errors

enum ChatError: LocalizedError {
    case runtimeNotReady
    case noModelConfigured
    case badStatus(Int)
    case streamInterrupted

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady:
            return "Orbit isn't ready. Start the runtime first."
        case .noModelConfigured:
            return "No model is configured. Choose one in Models."
        case .badStatus(let c) where c == 404:
            return "The AI model isn't available. Go to Models to check your setup."
        case .badStatus(let c) where c == 400:
            return "The request wasn't understood. Try starting a new chat."
        case .badStatus:
            return "Something went wrong. Try again in a moment."
        case .streamInterrupted:
            return "Response interrupted."
        }
    }
}

// MARK: - Protocol for testability

protocol ChatServiceProtocol: Sendable {
    /// Stream a chat completion.
    /// - Parameters:
    ///   - messages:     Full conversation history in oldest-first order.
    ///   - model:        Model ref to use.
    ///   - systemPrompt: Optional system message prepended before the history.
    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String
    ) -> AsyncThrowingStream<String, Error>
}

// MARK: - Real implementation

/// Calls the Mesh-LLM OpenAI-compatible streaming endpoint and yields content tokens.
final class ChatService: ChatServiceProtocol {
    let apiPort: Int

    init(apiPort: Int = 9337) {
        self.apiPort = apiPort
    }

    /// The exact URL posted to for chat completions. Exposed for regression testing.
    var completionsURL: URL {
        URL(string: "http://localhost:\(apiPort)/v1/chat/completions")!
    }

    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String = ""
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = URL(string: "http://localhost:\(apiPort)/v1/chat/completions") else {
                        continuation.finish(throwing: ChatError.badStatus(0))
                        return
                    }

                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("application/json",    forHTTPHeaderField: "Content-Type")
                    request.setValue("text/event-stream",   forHTTPHeaderField: "Accept")
                    request.setValue("no-cache",            forHTTPHeaderField: "Cache-Control")
                    request.timeoutInterval = 60

                    // Prepend system prompt when set
                    var allMessages = messages
                    let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedPrompt.isEmpty {
                        allMessages.insert(ChatRequestMessage(role: "system", content: trimmedPrompt), at: 0)
                    }

                    let body = ChatCompletionRequest(model: model, messages: allMessages)
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        continuation.finish(throwing: ChatError.badStatus(http.statusCode))
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        // SSE lines: "data: {...}" or "data: [DONE]" or comments/empty
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard !payload.isEmpty,
                              let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data),
                              let content = chunk.choices.first?.delta.content,
                              !content.isEmpty
                        else { continue }
                        continuation.yield(content)
                    }

                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
