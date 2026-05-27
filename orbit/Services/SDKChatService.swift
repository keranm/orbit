import Foundation
import MeshLLM

/// Routes inference to the right backend:
/// - Local models: SDK in-process FFI via node.inference.chat() (EmbeddedServingController)
/// - Mesh models:  HTTP SSE to the mesh-llm serve sidecar at localhost:9337
///   (the SDK's MeshClient.chat() hardcodes stream:false/max_tokens:64 — unusable for chat)
final class SDKChatService: ChatServiceProtocol, @unchecked Sendable {
    private let adapter: RuntimeAdapter?
    private let httpService = ChatService()

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
        AsyncThrowingStream<StreamEvent, Error>(bufferingPolicy: .unbounded) { continuation in
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

                // Connection state is the authoritative routing signal.
                // meshServeProcess.isRunning can be stale if sidecar crashed — don't rely on it alone.
                let onMesh = await MainActor.run(body: {
                    switch effectiveAdapter.meshConnectionState {
                    case .connectedPublic, .connectedPrivate: return true
                    default: return false
                    }
                })
                if onMesh {
                    // Ensure the HTTP sidecar is up before we attempt the request.
                    let sidecarRunning = await MainActor.run(body: { effectiveAdapter.meshServeProcess?.isRunning == true })
                    if !sidecarRunning {
                        await MainActor.run(body: { effectiveAdapter.restartMeshSidecar() })
                        try? await Task.sleep(for: .milliseconds(800))
                    }
                    let httpStream = self.httpService.streamCompletion(
                        messages: messages, model: model, systemPrompt: systemPrompt,
                        temperature: temperature, topP: topP, maxTokens: maxTokens,
                        frequencyPenalty: frequencyPenalty, presencePenalty: presencePenalty,
                        user: user)
                    do {
                        for try await event in httpStream {
                            guard !Task.isCancelled else { continuation.finish(); return }
                            continuation.yield(event)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                    return
                }

                guard let inference = await MainActor.run(body: { effectiveAdapter.node?.inference }) else {
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
