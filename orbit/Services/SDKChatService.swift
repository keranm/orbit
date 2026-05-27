import Foundation
import MeshLLM

/// Chat service that drives inference through the MeshLLM SDK's native in-process
/// API. The SDK does not expose an HTTP server on port 9337 — all inference is FFI.
///
/// For local models: uses node.inference.chat() (MeshNodeHandle).
/// For mesh models: uses meshClient.inference.chat() (MeshClientHandle) — the Node
/// handle requires a configured API base URL for remote peer routing; the Client
/// handle handles this correctly.
///
/// Pass a RuntimeAdapter at init for direct injection. If nil, the adapter is
/// resolved lazily from AppState.current at call time — safe for singletons like
/// NovaOverlayViewController that initialize before AppState is ready.
final class SDKChatService: ChatServiceProtocol, @unchecked Sendable {
    private let adapter: RuntimeAdapter?

    init(_ adapter: RuntimeAdapter? = nil) {
        self.adapter = adapter
    }

    // Abstracts over Node.Inference and Client.Inference which share the same
    // chat() signature but are different concrete types backed by different FFI handles.
    private enum InferenceProvider {
        case node(Node.Inference)
        case client(Client.Inference)

        func chat(_ request: MeshLLM.ChatRequest) -> AsyncThrowingStream<MeshLLM.Event, Error> {
            switch self {
            case .node(let n):   return n.chat(request)
            case .client(let c): return c.chat(request)
            }
        }
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
                let effectiveAdapter: RuntimeAdapter?
                if let a = self.adapter {
                    effectiveAdapter = a
                } else {
                    effectiveAdapter = await MainActor.run { AppState.current?.runtimeManager }
                }
                guard let effectiveAdapter else {
                    continuation.finish(throwing: ChatError.runtimeNotReady)
                    return
                }

                // Prefer meshClient (Client.inference) when on mesh — Node.inference
                // requires an API base URL for remote peer routing and will error.
                let provider: InferenceProvider
                let (meshInference, nodeInference) = await MainActor.run {
                    (effectiveAdapter.meshClient?.inference, effectiveAdapter.node?.inference)
                }
                if let mi = meshInference {
                    provider = .client(mi)
                } else if let ni = nodeInference {
                    provider = .node(ni)
                } else {
                    continuation.finish(throwing: ChatError.runtimeNotReady)
                    return
                }

                var sdkMessages: [MeshLLM.ChatMessage] = []
                let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sdkMessages.append(MeshLLM.ChatMessage(role: "system", content: trimmed))
                }
                sdkMessages.append(contentsOf: messages.map { MeshLLM.ChatMessage(role: $0.role, content: $0.content) })

                let request = MeshLLM.ChatRequest(model: model, messages: sdkMessages)
                let sdkStream = provider.chat(request)

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
