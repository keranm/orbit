import Foundation

@MainActor
final class MobileChatBridge {
    private let runtimeManager: RuntimeAdapter
    private let chatService: ChatServiceProtocol

    init(runtimeManager: RuntimeAdapter, chatService: ChatServiceProtocol) {
        self.runtimeManager = runtimeManager
        self.chatService = chatService
    }

    /// Dedicated URLSession for mobile chat completions — isolated from URLSession.shared
    /// so Mac and mobile requests never share connection pools or response caches.
    static let mobileSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config)
    }()

    func streamChat(
        modelId: String,
        messages: [ChatMessage],
        deviceId: String
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                // Validate runtime
                guard case .ready = runtimeManager.status else {
                    continuation.finish(throwing: MobileChatError.runtimeUnavailable)
                    return
                }

                // Validate model — check local installed models and (if connected) mesh models.
                let isLocalModel  = runtimeManager.installedModels.contains(where: { $0.id == modelId })
                let isMeshModel   = runtimeManager.meshConnectionState.isConnected &&
                                    runtimeManager.meshModels.contains(where: { $0.id == modelId })

                guard isLocalModel || isMeshModel else {
                    continuation.finish(throwing: MobileChatError.modelUnavailable)
                    return
                }

                // Map ChatMessage → ChatRequestMessage
                let requestMessages = messages.map { msg in
                    ChatRequestMessage(role: msg.role, content: msg.content)
                }

                // Determine which model ref to pass to chatService:
                // • Mesh model: pass the mesh model ID directly — mesh-llm routes by name.
                // • Local model: use runtimeManager.activeModelRef which is in the format
                //   mesh-llm expects (from config.toml), not the file-path format iOS sends.
                let runtimeModelRef: String
                if isMeshModel {
                    runtimeModelRef = modelId
                } else {
                    runtimeModelRef = runtimeManager.activeModelRef ?? modelId
                }

                let stream = chatService.streamCompletion(
                    messages: requestMessages,
                    model: runtimeModelRef,
                    systemPrompt: "",
                    temperature: nil, topP: nil, maxTokens: nil,
                    frequencyPenalty: nil, presencePenalty: nil,
                    user: "mobile-\(deviceId)"
                )

                do {
                    for try await event in stream {
                        switch event {
                        case .token(let text):
                            continuation.yield(text)
                        case .done:
                            continuation.finish()
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
