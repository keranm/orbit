import XCTest

@MainActor
final class SettingsUITests: XCTestCase {

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

    func test_settingsNavigation_fromSidebar() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 3))
    }

    func test_settingsGeneralSectionDefault() {
        app.buttons["Settings"].tap()
        // General is the default section — its label appears in the detail pane
        XCTAssertTrue(app.staticTexts["General"].waitForExistence(timeout: 3))
    }

    // MARK: - Privacy at a Glance panel

    func test_privacyAtAGlance_alwaysVisible() {
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Privacy at a glance"].waitForExistence(timeout: 5))
    }

    // MARK: - All section nav buttons exist

    func test_settingsSidebar_containsAllSections() {
        app.buttons["Settings"].tap()
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 3)

        // All four sections should be visible in the sidebar
        let expectedSections = ["General", "Models", "Privacy", "Reset"]
        for section in expectedSections {
            // Section names appear both as nav buttons and detail headers — find them
            let exists = app.staticTexts[section].exists || app.buttons[section].exists
            XCTAssertTrue(exists, "Section '\(section)' should be visible in settings sidebar")
        }
    }

    // MARK: - Accessibility tree diagnostic

    func test_dump_settings_accessibility_tree() {
        app.buttons["Settings"].tap()
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 3)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "settings-debug"; a.lifetime = .keepAlways; add(a)
        print("SETTINGS TREE:\n\(app.debugDescription.prefix(3000))")
        XCTAssertTrue(app.state == .runningForeground)
    }

    // MARK: - Screenshots

    func test_screenshot_settingsGeneral() {
        app.buttons["Settings"].tap()
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 3)
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Settings-General"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func test_screenshot_settingsPrivacy() {
        app.buttons["Settings"].tap()
        _ = app.staticTexts["Settings"].waitForExistence(timeout: 3)
        // Click Privacy section by its button label
        let privacyBtn = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Privacy'")).firstMatch
        if privacyBtn.waitForExistence(timeout: 3) { privacyBtn.click() }
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "Settings-Privacy"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
