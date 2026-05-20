import XCTest

/// UI tests for Stage 4 chat flows.
/// All tests use --mock-runtime (runtime = .ready) and --skip-onboarding.
final class ChatUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--mock-runtime", "--skip-onboarding"]
        app.launch()
        Thread.sleep(forTimeInterval: 1.5)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Chat home

    func test_chatHome_shows_greeting() {
        // With mock-runtime (.ready) and mock-model, chat home should show
        XCTAssertTrue(
            app.staticTexts["How can I help you today?"].waitForExistence(timeout: 4)
        )
    }

    func test_chatHome_has_composer_input() {
        XCTAssertTrue(
            app.textFields.firstMatch.waitForExistence(timeout: 4)
            || app.textViews.firstMatch.waitForExistence(timeout: 4)
        )
    }

    func test_chatHome_quick_action_cards_visible() {
        // Quick action cards are Button elements with .accessibilityLabel(title).
        // "Help me code" is one of the four card titles.
        // Check as a button (the card became a Button in Stage 6).
        let card = app.buttons["Help me code"]
        let found = card.waitForExistence(timeout: 8)
        XCTAssertTrue(found, "Quick action card 'Help me code' must be visible on chat home")
    }

    // MARK: - New Chat navigation

    func test_newChat_sidebar_button_navigates_home() {
        // Navigate away to Models, then New Chat brings us home
        app.buttons["Models"].tap()
        XCTAssertTrue(app.staticTexts["Models"].waitForExistence(timeout: 3))
        app.buttons["New Chat"].tap()
        XCTAssertTrue(
            app.staticTexts["How can I help you today?"].waitForExistence(timeout: 3)
        )
    }

    // MARK: - Diagnosics + screenshots

    func test_screenshot_chat_home() {
        _ = app.staticTexts["How can I help you today?"].waitForExistence(timeout: 4)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "stage4-chat-home"; a.lifetime = .keepAlways; add(a)
    }

    func test_dump_chat_accessibility_tree() {
        _ = app.staticTexts["How can I help you today?"].waitForExistence(timeout: 4)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "stage4-chat-debug"; a.lifetime = .keepAlways; add(a)
        print("CHAT TREE:\n\(app.debugDescription.prefix(2000))")
        XCTAssertTrue(app.state == .runningForeground)
    }
}
