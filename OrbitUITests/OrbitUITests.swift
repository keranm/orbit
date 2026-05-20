import XCTest

// Stage 0 UI test stub.
// Full coverage (onboarding, chat, models, settings flows) is added in Stage 3–5.
// These tests establish that the app launches and the V1 sidebar structure is correct.
final class OrbitUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // --skip-onboarding bypasses the first-run flow so tests see the main shell.
        app.launchArguments = ["--mock-runtime", "--skip-onboarding"]
        app.launch()
        Thread.sleep(forTimeInterval: 1.5)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Launch

    func test_app_launches_without_crash() {
        XCTAssertTrue(app.state == .runningForeground)
    }

    // MARK: - Sidebar structure

    func test_sidebar_contains_new_chat() {
        let newChat = app.buttons["New Chat"]
        XCTAssertTrue(newChat.waitForExistence(timeout: 3))
    }

    func test_sidebar_contains_models() {
        let models = app.buttons["Models"]
        XCTAssertTrue(models.waitForExistence(timeout: 3))
    }

    func test_sidebar_contains_settings() {
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 3))
    }

    func test_sidebar_contains_prompts() {
        // Prompts is a V1 feature — must appear in the sidebar.
        XCTAssertTrue(app.buttons["Prompts"].waitForExistence(timeout: 3))
    }

    func test_sidebar_does_not_contain_playground() {
        let playground = app.buttons["Playground"]
        XCTAssertFalse(playground.exists)
    }

    // MARK: - Navigation + Screenshots

    func test_tapping_models_shows_models_screen() {
        app.buttons["Models"].tap()
        XCTAssertTrue(app.staticTexts["Models"].waitForExistence(timeout: 2))
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))
    }

    func test_tapping_settings_shows_settings_screen() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 2))
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))
    }

    func test_tapping_new_chat_returns_to_home() {
        app.buttons["Models"].tap()
        app.buttons["New Chat"].tap()
        XCTAssertTrue(app.staticTexts["How can I help you today?"].waitForExistence(timeout: 2))
        add(XCTAttachment(screenshot: XCUIScreen.main.screenshot()))
    }

    // MARK: - Stage 0 visual screenshots

    func test_capture_new_chat_screenshot() {
        XCTAssertTrue(app.staticTexts["How can I help you today?"].waitForExistence(timeout: 4))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "stage0-new-chat"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_capture_models_screenshot() {
        app.buttons["Models"].tap()
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "stage0-models"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_capture_settings_screenshot() {
        app.buttons["Settings"].tap()
        sleep(1)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "stage0-settings"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
