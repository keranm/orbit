import Foundation

// MARK: - Request / response types

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatRequestMessage]
    let stream: Bool = true
    let temperature: Double?
    let topP: Double?
    let maxTokens: Int?
    let frequencyPenalty: Double?
    let presencePenalty: Double?

    init(model: String, messages: [ChatRequestMessage],
         temperature: Double? = nil, topP: Double? = nil,
         maxTokens: Int? = nil, frequencyPenalty: Double? = nil,
         presencePenalty: Double? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
    }
}

struct ChatRequestMessage: Encodable {
    let role: String
    let content: String
}

/// An event yielded by the streaming chat completion.
enum StreamEvent: Equatable {
    /// A content token from the assistant delta.
    case token(String)
    /// The stream finished with optional usage data from the server.
    case done(promptTokens: Int?, completionTokens: Int?)
}

/// A single SSE chunk from the streaming completions endpoint.
struct ChatCompletionChunk: Decodable {
    let choices: [ChunkChoice]
    let usage: Usage?

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

    struct Usage: Decodable {
        let promptTokens: Int?
        let completionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
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
    ) -> AsyncThrowingStream<StreamEvent, Error>

    /// Stream a chat completion with optional inference parameters.
    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String,
        temperature: Double?,
        topP: Double?,
        maxTokens: Int?,
        frequencyPenalty: Double?,
        presencePenalty: Double?
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

extension ChatServiceProtocol {
    /// Default: ignore advanced parameters, delegate to the basic method.
    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        streamCompletion(messages: messages, model: model, systemPrompt: systemPrompt)
    }
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
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        _stream(messages: messages, model: model, systemPrompt: systemPrompt)
    }

    /// Public entry point used by Pro Playground — forwards all inference parameters.
    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String,
        temperature: Double?,
        topP: Double?,
        maxTokens: Int?,
        frequencyPenalty: Double?,
        presencePenalty: Double?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        _stream(messages: messages, model: model, systemPrompt: systemPrompt,
                temperature: temperature, topP: topP, maxTokens: maxTokens,
                frequencyPenalty: frequencyPenalty, presencePenalty: presencePenalty)
    }

    // MARK: - Internal

    private func _stream(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String,
        temperature: Double? = nil,
        topP: Double? = nil,
        maxTokens: Int? = nil,
        frequencyPenalty: Double? = nil,
        presencePenalty: Double? = nil
    ) -> AsyncThrowingStream<StreamEvent, Error> {
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

                    let body = ChatCompletionRequest(
                        model: model, messages: allMessages,
                        temperature: temperature, topP: topP,
                        maxTokens: maxTokens,
                        frequencyPenalty: frequencyPenalty,
                        presencePenalty: presencePenalty
                    )
                    request.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        continuation.finish(throwing: ChatError.badStatus(http.statusCode))
                        return
                    }

                    var finalUsage: (prompt: Int, completion: Int)?

                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard !payload.isEmpty,
                              let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: data)
                        else { continue }

                        if let usage = chunk.usage {
                            finalUsage = (usage.promptTokens ?? 0, usage.completionTokens ?? 0)
                        }

                        if let content = chunk.choices.first?.delta.content, !content.isEmpty {
                            continuation.yield(.token(content))
                        }
                    }

                    continuation.yield(.done(
                        promptTokens: finalUsage?.prompt,
                        completionTokens: finalUsage?.completion
                    ))
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
