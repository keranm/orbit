import XCTest
import SwiftData
@testable import orbit

/// Unit tests for ChatViewModel state machine.
@MainActor
final class ChatViewModelTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUpWithError() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Chat.self, Message.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDownWithError() throws {
        container = nil
        context = nil
    }

    // MARK: - Helpers

    private func makeChat(model: String = "mock-model") -> Chat {
        let chat = Chat(modelRef: model)
        context.insert(chat)
        return chat
    }

    private func makeVM(
        chat: Chat,
        service: any ChatServiceProtocol = MockChatService()
    ) -> ChatViewModel {
        ChatViewModel(chat: chat, modelContext: context, appState: nil, service: service)
    }

    // MARK: - Initial state

    func test_initialState_sortedMessagesEmpty() {
        let chat = makeChat()
        let vm = makeVM(chat: chat)
        XCTAssertTrue(vm.sortedMessages.isEmpty)
    }

    func test_initialState_notStreaming() {
        let vm = makeVM(chat: makeChat())
        XCTAssertFalse(vm.isStreaming)
    }

    func test_initialState_canSendFalseWithEmptyInput() {
        let vm = makeVM(chat: makeChat())
        vm.inputText = ""
        XCTAssertFalse(vm.canSend)
    }

    func test_canSend_trueWithText_whenNoAppState() {
        let vm = makeVM(chat: makeChat())
        vm.inputText = "Hello"
        // appState is nil — runtimeIsReady defaults to true for test path
        XCTAssertTrue(vm.canSend)
    }

    func test_canSend_falseWhileStreaming() async {
        let slowService = MockChatService(tokens: ["tok"], delay: 0.5)
        let vm = makeVM(chat: makeChat(), service: slowService)
        vm.inputText = "Hello"
        let sendTask = Task { await vm.send() }
        // Give it a moment to start streaming
        try? await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(vm.canSend)
        sendTask.cancel()
    }

    // MARK: - send()

    func test_send_addsUserMessage() async {
        let mock = MockChatService(tokens: ["Hi"])
        let vm = makeVM(chat: makeChat(), service: mock)
        vm.inputText = "Hello"
        await vm.send()
        let userMsgs = vm.sortedMessages.filter { $0.role == "user" }
        XCTAssertEqual(userMsgs.count, 1)
        XCTAssertEqual(userMsgs.first?.content, "Hello")
    }

    func test_send_clearsInputText() async {
        let vm = makeVM(chat: makeChat(), service: MockChatService(tokens: []))
        vm.inputText = "Test message"
        await vm.send()
        XCTAssertTrue(vm.inputText.isEmpty)
    }

    func test_send_addsAssistantMessage() async {
        let mock = MockChatService(tokens: ["Hello", "!"])
        let vm = makeVM(chat: makeChat(), service: mock)
        vm.inputText = "Hi"
        await vm.send()
        let assistantMsgs = vm.sortedMessages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1)
    }

    func test_send_assemblesTokensInOrder() async {
        let mock = MockChatService(tokens: ["The", " ", "answer", " is", " 42"])
        let vm = makeVM(chat: makeChat(), service: mock)
        vm.inputText = "Question"
        await vm.send()
        let reply = vm.sortedMessages.last
        XCTAssertEqual(reply?.content, "The answer is 42")
    }

    func test_send_setsNotStreamingAfterCompletion() async {
        let vm = makeVM(chat: makeChat(), service: MockChatService(tokens: ["done"]))
        vm.inputText = "Hello"
        await vm.send()
        XCTAssertFalse(vm.isStreaming)
    }

    func test_send_streamErrorSetOnFailure() async {
        let mock = MockChatService(error: ChatError.runtimeNotReady)
        let vm = makeVM(chat: makeChat(), service: mock)
        vm.inputText = "Hello"
        await vm.send()
        XCTAssertFalse(vm.isStreaming)
        XCTAssertNotNil(vm.streamError)
        XCTAssertFalse(vm.streamError!.isEmpty)
    }

    func test_send_emptyInput_doesNothing() async {
        let vm = makeVM(chat: makeChat())
        vm.inputText = "  "
        await vm.send()
        XCTAssertTrue(vm.sortedMessages.isEmpty)
    }

    // MARK: - autoTitle

    func test_send_setsAutoTitleFromFirstMessage() async {
        let chat = makeChat()
        let vm = makeVM(chat: chat, service: MockChatService(tokens: []))
        vm.inputText = "What is the capital of France?"
        await vm.send()
        XCTAssertNotEqual(chat.title, "New Chat")
        XCTAssertTrue(chat.title.contains("capital of France"))
    }

    func test_send_doesNotOverrideExistingTitle() async {
        let chat = makeChat()
        chat.title = "My saved title"
        let vm = makeVM(chat: chat, service: MockChatService(tokens: []))
        vm.inputText = "Another message"
        await vm.send()
        XCTAssertEqual(chat.title, "My saved title")
    }

    // MARK: - cancelStream

    func test_cancel_stopsStreaming() async {
        let slowService = MockChatService(tokens: Array(repeating: "tok", count: 100), delay: 0.05)
        let vm = makeVM(chat: makeChat(), service: slowService)
        vm.inputText = "Hello"
        Task { await vm.send() }
        try? await Task.sleep(for: .milliseconds(100))
        vm.cancelStream()
        XCTAssertFalse(vm.isStreaming)
    }

    // MARK: - sendIfNeeded

    func test_sendIfNeeded_startsStreamIfLastMsgIsUser() async {
        let chat = makeChat()
        let userMsg = Message(role: "user", content: "Prompt")
        chat.messages.append(userMsg)
        try? context.save()

        let vm = makeVM(chat: chat, service: MockChatService(tokens: ["Response"]))
        await vm.sendIfNeeded()

        let assistantMsgs = vm.sortedMessages.filter { $0.role == "assistant" }
        XCTAssertEqual(assistantMsgs.count, 1)
    }

    func test_sendIfNeeded_doesNothingIfLastMsgIsAssistant() async {
        let chat = makeChat()
        let userMsg  = Message(role: "user",      content: "Hi")
        let asstMsg  = Message(role: "assistant",  content: "Hello!")
        chat.messages.append(contentsOf: [userMsg, asstMsg])
        try? context.save()

        let vm = makeVM(chat: chat, service: MockChatService(tokens: ["token"]))
        await vm.sendIfNeeded()

        // Still only 2 messages — no new assistant message
        XCTAssertEqual(vm.sortedMessages.count, 2)
    }
}

// MockChatService with delay support is now in ChatServiceTests.swift.
// The delay parameter is part of the main init(tokens:error:delay:).
