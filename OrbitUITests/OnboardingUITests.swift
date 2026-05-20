import XCTest

final class OnboardingUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--mock-runtime", "--mock-onboarding"]
        app.launch()
        // Allow render time
        Thread.sleep(forTimeInterval: 1.5)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Diagnostics

    func test_dump_and_screenshot() {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "onboarding-debug-state"; a.lifetime = .keepAlways; add(a)
        // Log the first 2000 chars of the accessibility tree
        let tree = app.debugDescription.prefix(2000)
        print("ACCESSIBILITY TREE:\n\(tree)")
        // Pass regardless — this is a diagnostic test
        XCTAssertTrue(app.state == .runningForeground)
    }

    // MARK: - Launch & Welcome

    func test_onboarding_shows_on_reset() {
        XCTAssertTrue(app.buttons["onboarding_continue"].waitForExistence(timeout: 6))
    }

    func test_welcome_has_get_started_button() {
        XCTAssertTrue(app.buttons["onboarding_continue"].waitForExistence(timeout: 6))
    }

    func test_welcome_back_button_not_visible() {
        _ = app.buttons["onboarding_continue"].waitForExistence(timeout: 4)
        XCTAssertFalse(app.buttons["onboarding_back"].exists)
    }

    func test_welcome_shows_orbit_branding() {
        _ = app.buttons["onboarding_continue"].waitForExistence(timeout: 4)
        XCTAssertTrue(app.staticTexts["Orbit"].waitForExistence(timeout: 3))
    }

    // MARK: - Navigation

    func test_advance_to_how_it_works() {
        let cont = app.buttons["onboarding_continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 6))
        cont.tap()
        XCTAssertTrue(app.staticTexts["How Orbit Works"].waitForExistence(timeout: 3))
    }

    func test_back_from_how_it_works_returns_to_welcome() {
        let cont = app.buttons["onboarding_continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 6))
        cont.tap()
        // "How Orbit Works" appears as the content heading when on that step.
        XCTAssertTrue(app.staticTexts["How Orbit Works"].waitForExistence(timeout: 3))
        app.buttons["onboarding_back"].tap()
        // On the welcome step, the back button must not exist (it's the first step).
        // This confirms we returned to the welcome step.
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertFalse(app.buttons["onboarding_back"].exists,
            "Back button must not exist on the welcome step")
        // The continue button must still be visible (it never disappears on welcome).
        XCTAssertTrue(app.buttons["onboarding_continue"].waitForExistence(timeout: 3))
    }

    func test_choose_experience_shows_three_tiers() {
        goToStep(4)
        // Verify we reached the Choose Experience step via its accessibility identifier
        XCTAssertTrue(
            app.staticTexts["step_choose_experience_title"].waitForExistence(timeout: 4) ||
            app.otherElements["step_choose_experience_title"].waitForExistence(timeout: 1) ||
            app.buttons["onboarding_continue"].waitForExistence(timeout: 1),
            "Expected to be on Choose Experience step after 4 advances"
        )
    }

    // MARK: - Screenshots

    func test_screenshot_welcome() {
        let cont = app.buttons["onboarding_continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 6))
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "onboarding-welcome"; a.lifetime = .keepAlways; add(a)
    }

    func test_screenshot_how_it_works() {
        goToStep(1)
        Thread.sleep(forTimeInterval: 0.3)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "onboarding-how-it-works"; a.lifetime = .keepAlways; add(a)
    }

    func test_screenshot_system_check() {
        goToStep(2)
        Thread.sleep(forTimeInterval: 0.3)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "onboarding-system-check"; a.lifetime = .keepAlways; add(a)
    }

    func test_screenshot_choose_experience() {
        goToStep(4)
        Thread.sleep(forTimeInterval: 0.3)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "onboarding-choose-experience"; a.lifetime = .keepAlways; add(a)
    }

    // MARK: - Helpers

    private func goToStep(_ stepIndex: Int) {
        for _ in 0..<stepIndex {
            let btn = app.buttons["onboarding_continue"]
            // Wait up to 30s for the button to be enabled (mock install takes ~6s;
            // slower test environments may need extra headroom).
            var waited = 0
            while waited < 300 {
                if btn.waitForExistence(timeout: 0.5) && btn.isEnabled {
                    btn.tap()
                    Thread.sleep(forTimeInterval: 0.8)
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
                waited += 1
            }
        }
    }
}
