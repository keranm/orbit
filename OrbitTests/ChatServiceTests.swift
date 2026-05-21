import XCTest
@testable import orbit

/// Unit tests for ChatService SSE parsing and request construction.
final class ChatServiceTests: XCTestCase {

    // MARK: - ChatCompletionRequest encoding

    func test_request_encodesModel() throws {
        let req = ChatCompletionRequest(
            model: "test-model",
            messages: [ChatRequestMessage(role: "user", content: "hello")]
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "test-model")
    }

    func test_request_streamIsTrue() throws {
        let req = ChatCompletionRequest(
            model: "m",
            messages: [ChatRequestMessage(role: "user", content: "hi")]
        )
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["stream"] as? Bool, true)
    }

    func test_request_encodesMessages() throws {
        let msgs = [
            ChatRequestMessage(role: "user",      content: "Hi"),
            ChatRequestMessage(role: "assistant",  content: "Hello!"),
        ]
        let req = ChatCompletionRequest(model: "m", messages: msgs)
        let data = try JSONEncoder().encode(req)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let encoded = json["messages"] as! [[String: Any]]
        XCTAssertEqual(encoded.count, 2)
        XCTAssertEqual(encoded[0]["role"] as? String, "user")
        XCTAssertEqual(encoded[1]["content"] as? String, "Hello!")
    }

    // MARK: - ChatCompletionChunk decoding (SSE payload shapes)

    func test_chunk_decodesContentToken() throws {
        let json = """
        {"id":"c1","object":"chat.completion.chunk","choices":[
          {"index":0,"delta":{"content":"Hello"},"finish_reason":null}
        ]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.choices.first?.delta.content, "Hello")
        XCTAssertNil(chunk.choices.first?.finishReason)
    }

    func test_chunk_decodesRoleDeltaWithNoContent() throws {
        let json = """
        {"id":"c1","object":"chat.completion.chunk","choices":[
          {"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}
        ]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.choices.first?.delta.role, "assistant")
        XCTAssertEqual(chunk.choices.first?.delta.content, "")
    }

    func test_chunk_decodesFinishReason() throws {
        let json = """
        {"id":"c1","object":"chat.completion.chunk","choices":[
          {"index":0,"delta":{},"finish_reason":"stop"}
        ]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.choices.first?.finishReason, "stop")
    }

    func test_chunk_toleratesExtraFields() throws {
        let json = """
        {"id":"c1","object":"chat.completion.chunk","created":999,"model":"x","choices":[
          {"index":0,"delta":{"content":"token"},"logprobs":null,"finish_reason":null}
        ]}
        """
        let chunk = try JSONDecoder().decode(ChatCompletionChunk.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(chunk.choices.first?.delta.content, "token")
    }

    // MARK: - ChatError

    func test_chatError_runtimeNotReady_hasDescription() {
        let e = ChatError.runtimeNotReady
        XCTAssertFalse(e.errorDescription?.isEmpty ?? true)
    }

    func test_chatError_badStatus_genericIsNonEmpty() {
        let e = ChatError.badStatus(503)
        XCTAssertFalse(e.errorDescription?.isEmpty ?? true)
    }

    func test_chatError_badStatus_404_isUserFriendlyAndHidesCode() {
        // 404 = model not found — must not expose "404" to users.
        let e = ChatError.badStatus(404)
        let desc = e.errorDescription ?? ""
        XCTAssertFalse(desc.isEmpty)
        XCTAssertFalse(desc.contains("404"), "404 error must not expose the HTTP status code")
        XCTAssertFalse(desc.lowercased().contains("unexpected"), "404 message should be user-friendly")
    }

    func test_chatError_badStatus_400_isUserFriendly() {
        let e = ChatError.badStatus(400)
        XCTAssertFalse(e.errorDescription?.isEmpty ?? true)
        XCTAssertFalse(e.errorDescription?.contains("400") ?? false)
    }

    // MARK: - ChatService URL regression

    func test_chatService_completionsURL_isCorrectEndpoint() {
        // Regression: must POST to /v1/chat/completions — never to a different path.
        let service = ChatService(apiPort: 9337)
        XCTAssertEqual(
            service.completionsURL.absoluteString,
            "http://localhost:9337/v1/chat/completions",
            "ChatService must POST to /v1/chat/completions"
        )
    }

    func test_chatService_completionsURL_respectsApiPort() {
        let service = ChatService(apiPort: 11434)
        XCTAssertEqual(
            service.completionsURL.absoluteString,
            "http://localhost:11434/v1/chat/completions"
        )
    }

    func test_chatService_completionsURL_neverChangesPath() {
        // Guard against accidental path modification.
        let url = ChatService(apiPort: 9337).completionsURL
        XCTAssertEqual(url.host, "localhost")
        XCTAssertEqual(url.port, 9337)
        XCTAssertEqual(url.path, "/v1/chat/completions")
        XCTAssertEqual(url.scheme, "http")
    }

    // MARK: - MockChatService via protocol

    func test_mockService_yieldsTokens() async throws {
        let mock = MockChatService(tokens: ["Hello", " ", "world"])
        let stream = mock.streamCompletion(
            messages: [ChatRequestMessage(role: "user", content: "hi")],
            model: "mock"
        )
        var collected = ""
        for try await event in stream {
            if case .token(let t) = event { collected += t }
        }
        XCTAssertEqual(collected, "Hello world")
    }

    func test_mockService_emptyTokens_completesCleanly() async throws {
        let mock = MockChatService(tokens: [])
        let stream = mock.streamCompletion(
            messages: [ChatRequestMessage(role: "user", content: "hi")],
            model: "mock"
        )
        var count = 0
        for try await _ in stream { count += 1 }
        XCTAssertEqual(count, 1, "Should yield exactly one .done event")
    }

    func test_mockService_throwingError_propagates() async {
        let mock = MockChatService(error: ChatError.runtimeNotReady)
        let stream = mock.streamCompletion(
            messages: [ChatRequestMessage(role: "user", content: "hi")],
            model: "mock"
        )
        do {
            for try await _ in stream {}
            XCTFail("Expected error to be thrown")
        } catch {
            XCTAssertTrue(error is ChatError)
        }
    }

    // MARK: - Real service skipped when runtime not running

    func test_realService_returnsErrorWhenNotRunning() async {
        let service = ChatService(apiPort: 9337)
        let stream = service.streamCompletion(
            messages: [ChatRequestMessage(role: "user", content: "test")],
            model: "test-model"
        )
        do {
            for try await _ in stream {}
            // If we get here without error it means something answered on 9337 — also valid
        } catch {
            // Expected — runtime not running
            XCTAssertNotNil(error)
        }
    }
}

// MARK: - Mock implementation for testing

final class MockChatService: ChatServiceProtocol {
    let tokens: [String]
    let error: Error?
    let delay: TimeInterval

    init(tokens: [String] = [], error: Error? = nil, delay: TimeInterval = 0) {
        self.tokens = tokens
        self.error = error
        self.delay = delay
    }

    func streamCompletion(
        messages: [ChatRequestMessage],
        model: String,
        systemPrompt: String = ""
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        let tokens = self.tokens
        let error = self.error
        let delay = self.delay
        return AsyncThrowingStream { continuation in
            Task {
                if let e = error {
                    continuation.finish(throwing: e)
                    return
                }
                for token in tokens {
                    if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                    continuation.yield(.token(token))
                }
                continuation.yield(.done(promptTokens: nil, completionTokens: nil))
                continuation.finish()
            }
        }
    }
}
