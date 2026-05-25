import Foundation

struct ChatRequestMessage: Encodable {
    let role: String
    let content: String
}

enum StreamEvent: Equatable {
    case token(String)
    case done(promptTokens: Int?, completionTokens: Int?)
}

enum ChatError: LocalizedError {
    case runtimeNotReady
    case noModelConfigured

    var errorDescription: String? {
        switch self {
        case .runtimeNotReady:
            return "Orbit isn't ready. Start the runtime first."
        case .noModelConfigured:
            return "No model is configured. Choose one in Models."
        }
    }
}

protocol ChatServiceProtocol: Sendable {
    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String,
        temperature: Double?,
        topP: Double?,
        maxTokens: Int?,
        frequencyPenalty: Double?,
        presencePenalty: Double?,
        user: String?
    ) -> AsyncThrowingStream<StreamEvent, Error>
}

extension ChatServiceProtocol {
    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String = ""
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        streamCompletion(
            messages: messages, model: model, systemPrompt: systemPrompt,
            temperature: nil, topP: nil, maxTokens: nil,
            frequencyPenalty: nil, presencePenalty: nil, user: nil
        )
    }
}

final class ChatService: ChatServiceProtocol {
    private static let completionsURL = URL(string: "http://localhost:9337/v1/chat/completions")!

    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String,
        temperature: Double?,
        topP: Double?,
        maxTokens: Int?,
        frequencyPenalty: Double?,
        presencePenalty: Double?,
        user: String?
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var allMessages = messages
                let trimmedPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedPrompt.isEmpty {
                    allMessages.insert(ChatRequestMessage(role: "system", content: trimmedPrompt), at: 0)
                }

                var body: [String: Any] = [
                    "model": model,
                    "messages": allMessages.map { ["role": $0.role, "content": $0.content] },
                    "stream": true
                ]
                if let temperature { body["temperature"] = temperature }
                if let topP { body["top_p"] = topP }
                if let maxTokens { body["max_tokens"] = maxTokens }
                if let frequencyPenalty { body["frequency_penalty"] = frequencyPenalty }
                if let presencePenalty { body["presence_penalty"] = presencePenalty }
                if let user { body["user"] = user }

                guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
                    continuation.finish(throwing: ChatError.runtimeNotReady)
                    return
                }

                var request = URLRequest(url: Self.completionsURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = bodyData

                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                        continuation.finish(throwing: ChatError.runtimeNotReady)
                        return
                    }

                    var promptTokens: Int?
                    var completionTokens: Int?

                    for try await line in bytes.lines {
                        guard !Task.isCancelled else {
                            continuation.finish()
                            return
                        }
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            continuation.yield(.done(promptTokens: promptTokens, completionTokens: completionTokens))
                            continuation.finish()
                            return
                        }
                        guard let data = payload.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }

                        if let choices = json["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let content = delta["content"] as? String, !content.isEmpty {
                            continuation.yield(.token(content))
                        }
                        if let usage = json["usage"] as? [String: Any] {
                            promptTokens = usage["prompt_tokens"] as? Int
                            completionTokens = usage["completion_tokens"] as? Int
                        }
                    }

                    continuation.yield(.done(promptTokens: promptTokens, completionTokens: completionTokens))
                    continuation.finish()
                } catch {
                    if Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
        }
    }
}
