import XCTest

@MainActor
final class ModelsUITests: XCTestCase {

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

    // MARK: - Navigation

    func test_modelsNavigation_fromSidebar() {
        app.buttons["Models"].tap()
        XCTAssertTrue(app.staticTexts["Models"].waitForExistence(timeout: 5))
    }

    // MARK: - Tabs

    func test_modelsScreen_localTabExists() {
        app.buttons["Models"].tap()
        XCTAssertTrue(app.buttons["Local"].waitForExistence(timeout: 3))
    }

    func test_modelsScreen_meshNetworkTabExists() {
        app.buttons["Models"].tap()
        XCTAssertTrue(app.buttons["Mesh Network"].waitForExistence(timeout: 3))
    }

    // MARK: - Empty state

    func test_modelsScreen_emptyState_showsBrowseOrErrorContent() {
        app.buttons["Models"].tap()
        // With mock-runtime (no real binary), the view either shows empty state
        // ("Browse models" or "No models installed") or a recoverable error.
        let expectation = [
            app.staticTexts["No models installed"],
            app.buttons["Browse models"],
            app.staticTexts["Couldn't load your models. Try refreshing."],
        ].map { $0.waitForExistence(timeout: 5) }
        XCTAssertTrue(expectation.contains(true), "Expected empty state or error state to be visible")
    }

    // MARK: - Screenshot

    func test_screenshot_modelsView() {
        app.buttons["Models"].tap()
        _ = app.staticTexts["Models"].waitForExistence(timeout: 3)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "ModelsView-Stage5"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Accessibility tree diagnostic

    func test_dump_models_accessibility_tree() {
        app.buttons["Models"].tap()
        _ = app.staticTexts["Models"].waitForExistence(timeout: 3)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "models-debug"; a.lifetime = .keepAlways; add(a)
        print("MODELS TREE:\n\(app.debugDescription.prefix(3000))")
        XCTAssertTrue(app.state == .runningForeground)
    }

    // MARK: - Return to new chat

    func test_modelsScreen_backToNewChat() {
        app.buttons["Models"].tap()
        XCTAssertTrue(app.staticTexts["Models"].waitForExistence(timeout: 3))
        app.buttons["New Chat"].tap()
        XCTAssertTrue(
            app.staticTexts["How can I help you today?"].waitForExistence(timeout: 3)
        )
    }
}
