import XCTest
@testable import orbit

/// Unit tests for ReasoningParser — covers parsing, streaming edge cases, and toggle behaviour.
final class ReasoningParserTests: XCTestCase {

    // MARK: - No reasoning

    func test_parse_plainText_hasNoReasoning() {
        let result = ReasoningParser.parse("Hello, world!")
        XCTAssertFalse(result.hasReasoning)
        XCTAssertEqual(result.visible, "Hello, world!")
        XCTAssertFalse(result.isReasoningInProgress)
    }

    func test_parse_emptyString_hasNoReasoning() {
        let result = ReasoningParser.parse("")
        XCTAssertFalse(result.hasReasoning)
        XCTAssertEqual(result.visible, "")
        XCTAssertFalse(result.isReasoningInProgress)
    }

    // MARK: - Complete reasoning block

    func test_parse_completeThinkBlock_extractsReasoning() {
        let text = "<think>I need to think about this</think>Here is my answer."
        let result = ReasoningParser.parse(text)
        XCTAssertTrue(result.hasReasoning)
        XCTAssertEqual(result.reasoning, "I need to think about this")
        XCTAssertEqual(result.visible, "Here is my answer.")
        XCTAssertFalse(result.isReasoningInProgress)
    }

    func test_parse_thinkBlockAtEnd_visibleIsEmpty() {
        let text = "<think>Some reasoning</think>"
        let result = ReasoningParser.parse(text)
        XCTAssertTrue(result.hasReasoning)
        XCTAssertEqual(result.reasoning, "Some reasoning")
        XCTAssertEqual(result.visible, "")
        XCTAssertFalse(result.isReasoningInProgress)
    }

    func test_parse_multilineThinkBlock() {
        let text = "<think>\nLine one\nLine two\n</think>Answer"
        let result = ReasoningParser.parse(text)
        XCTAssertTrue(result.hasReasoning)
        XCTAssertTrue(result.reasoning.contains("Line one"))
        XCTAssertTrue(result.reasoning.contains("Line two"))
        XCTAssertEqual(result.visible, "Answer")
    }

    func test_parse_caseInsensitive_uppercase() {
        let text = "<THINK>reasoning</THINK>visible"
        let result = ReasoningParser.parse(text)
        XCTAssertTrue(result.hasReasoning)
        XCTAssertEqual(result.reasoning, "reasoning")
        XCTAssertEqual(result.visible, "visible")
    }

    func test_parse_textBeforeThinkBlock_preserved() {
        let text = "Prefix text<think>reasoning</think>Suffix"
        let result = ReasoningParser.parse(text)
        XCTAssertEqual(result.visible, "Prefix textSuffix")
        XCTAssertEqual(result.reasoning, "reasoning")
    }

    // MARK: - Streaming / in-progress

    func test_parse_unclosedThinkBlock_isInProgress() {
        let text = "<think>Still thinking..."
        let result = ReasoningParser.parse(text)
        XCTAssertTrue(result.isReasoningInProgress)
        XCTAssertEqual(result.reasoning, "Still thinking...")
        XCTAssertEqual(result.visible, "")
    }

    func test_parse_thinkBlockJustOpened_isInProgress() {
        let result = ReasoningParser.parse("<think>")
        XCTAssertTrue(result.isReasoningInProgress)
        XCTAssertFalse(result.hasReasoning)  // empty reasoning block
    }

    func test_parse_partialTokenStream_handlesGracefully() {
        // Simulates tokens arriving mid-tag: "<thi" (incomplete opening tag)
        // Should be treated as plain visible text
        let result = ReasoningParser.parse("Hello <thi")
        XCTAssertFalse(result.isReasoningInProgress)
        XCTAssertEqual(result.visible, "Hello <thi")
    }

    func test_parse_streamingComplete_notInProgress() {
        let text = "<think>done thinking</think>Final answer"
        let result = ReasoningParser.parse(text)
        XCTAssertFalse(result.isReasoningInProgress)
    }

    // MARK: - Multiple blocks

    func test_parse_multipleThinkBlocks_combinesReasoning() {
        let text = "<think>first</think>mid<think>second</think>end"
        let result = ReasoningParser.parse(text)
        XCTAssertTrue(result.reasoning.contains("first"))
        XCTAssertTrue(result.reasoning.contains("second"))
        XCTAssertEqual(result.visible, "midend")
    }

    // MARK: - visibleContent convenience

    func test_visibleContent_stripsThinkTags() {
        let text = "<think>internal</think>External response"
        XCTAssertEqual(ReasoningParser.visibleContent(text), "External response")
    }

    func test_visibleContent_plainText_unchanged() {
        XCTAssertEqual(ReasoningParser.visibleContent("Just text"), "Just text")
    }

    func test_visibleContent_emptyString() {
        XCTAssertEqual(ReasoningParser.visibleContent(""), "")
    }

    // MARK: - Reasoning visibility flag

    func test_showReasoning_defaultIsFalse() {
        // The default value must be false (OFF) — reasoning hidden by default
        // Verify by reading UserDefaults directly (key not set = default)
        UserDefaults.standard.removeObject(forKey: "showModelReasoning")
        let defaultValue = UserDefaults.standard.bool(forKey: "showModelReasoning")
        XCTAssertFalse(defaultValue, "showModelReasoning must default to false")
    }

    func test_showReasoning_persistsTrue() {
        UserDefaults.standard.set(true, forKey: "showModelReasoning")
        XCTAssertTrue(UserDefaults.standard.bool(forKey: "showModelReasoning"))
        UserDefaults.standard.removeObject(forKey: "showModelReasoning")
    }

    func test_showReasoning_persistsFalse() {
        UserDefaults.standard.set(false, forKey: "showModelReasoning")
        XCTAssertFalse(UserDefaults.standard.bool(forKey: "showModelReasoning"))
        UserDefaults.standard.removeObject(forKey: "showModelReasoning")
    }

    // MARK: - Real-world Qwen3 response format

    func test_parse_qwen3StyleResponse() {
        let qwenResponse = """
        <think>
        Okay, the user wants me to reply with "VALIDATION_OK". Let me do that.
        </think>
        VALIDATION_OK
        """
        let result = ReasoningParser.parse(qwenResponse)
        XCTAssertTrue(result.hasReasoning)
        XCTAssertTrue(result.reasoning.contains("VALIDATION_OK"))
        XCTAssertEqual(result.visible, "VALIDATION_OK")
        XCTAssertFalse(result.isReasoningInProgress)
    }

    func test_parse_qwen3InProgress_duringStreaming() {
        // Partial response — think block not yet closed
        let partial = "<think>\nOkay, let me think about this carefully. The user asked for"
        let result = ReasoningParser.parse(partial)
        XCTAssertTrue(result.isReasoningInProgress)
        XCTAssertEqual(result.visible, "")
        XCTAssertTrue(result.hasReasoning)
    }
}
