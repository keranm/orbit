import Foundation
import MeshLLM

/// Chat service that drives inference through the MeshLLM SDK's native in-process
/// API (node.inference.chat). The SDK does not expose an HTTP server on port 9337 —
/// all inference is FFI, so ChatService (HTTP) was always broken after the SDK migration.
///
/// Pass a RuntimeAdapter at init for direct injection. If nil, the adapter is
/// resolved lazily from AppState.current at call time — safe for singletons like
/// NovaOverlayViewController that initialize before AppState is ready.
final class SDKChatService: ChatServiceProtocol, @unchecked Sendable {
    private let adapter: RuntimeAdapter?

    init(_ adapter: RuntimeAdapter? = nil) {
        self.adapter = adapter
    }

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
                let effectiveAdapter = self.adapter ?? (await MainActor.run { AppState.current?.runtimeManager })
                guard let effectiveAdapter else {
                    continuation.finish(throwing: ChatError.runtimeNotReady)
                    return
                }

                guard let inference = await MainActor.run(body: { effectiveAdapter.node?.inference }) else {
                    continuation.finish(throwing: ChatError.runtimeNotReady)
                    return
                }

                var sdkMessages: [ChatMessage] = []
                let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sdkMessages.append(ChatMessage(role: "system", content: trimmed))
                }
                sdkMessages.append(contentsOf: messages.map { ChatMessage(role: $0.role, content: $0.content) })

                let request = ChatRequest(model: model, messages: sdkMessages)
                let sdkStream = inference.chat(request)

                do {
                    for try await event in sdkStream {
                        guard !Task.isCancelled else { continuation.finish(); return }
                        switch event {
                        case .tokenDelta(_, let delta):
                            continuation.yield(.token(delta))
                        case .completed:
                            continuation.yield(.done(promptTokens: nil, completionTokens: nil))
                            continuation.finish()
                            return
                        case .failed(_, let errorMsg):
                            struct SDKError: LocalizedError {
                                let msg: String
                                var errorDescription: String? { msg }
                            }
                            continuation.finish(throwing: SDKError(msg: errorMsg))
                            return
                        default:
                            break
                        }
                    }
                    continuation.yield(.done(promptTokens: nil, completionTokens: nil))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
