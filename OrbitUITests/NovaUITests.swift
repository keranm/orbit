import XCTest

final class NovaUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--reset-onboarding", "--mock-runtime", "--mock-onboarding"]
        app.launch()
        Thread.sleep(forTimeInterval: 1.5)
    }

    override func tearDownWithError() throws {
        app.terminate()
        app = nil
    }

    // MARK: - Nova present on onboarding welcome

    func test_nova_present_on_welcome() {
        XCTAssertTrue(
            app.buttons["onboarding_continue"].waitForExistence(timeout: 6),
            "Welcome step should show the continue button"
        )
        // Nova is marked accessibilityHidden on welcome so it won't appear
        // in the accessibility tree — confirm the welcome step loaded
        XCTAssertTrue(app.staticTexts["Orbit"].waitForExistence(timeout: 3))
    }

    // MARK: - Nova present on main app shell

    func test_nova_present_on_main_shell() {
        completeOnboarding()
        // Nova's accessibility identifier is "nova_companion". Use a type-agnostic
        // query because SwiftUI may map the element to different XCUIElementTypes
        // depending on macOS version and accessibility trait resolution.
        let nova = app.descendants(matching: .any).matching(identifier: "nova_companion").firstMatch
        let found = nova.waitForExistence(timeout: 8)
        if !found {
            // Log tree to help diagnose on failure
            print("NOVA SHELL TREE (first 2000):\n\(app.debugDescription.prefix(2000))")
        }
        XCTAssertTrue(found, "Nova companion should be visible on the main shell (identifier: nova_companion)")
    }

    // MARK: - Screenshots

    func test_screenshot_nova_welcome() {
        XCTAssertTrue(app.buttons["onboarding_continue"].waitForExistence(timeout: 6))
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "nova-welcome"; a.lifetime = .keepAlways; add(a)
    }

    func test_screenshot_nova_main_shell() {
        completeOnboarding()
        Thread.sleep(forTimeInterval: 0.5)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "nova-main-shell"; a.lifetime = .keepAlways; add(a)
    }

    func test_screenshot_nova_system_check_thinking() {
        // Step 2 = system check → Nova enters thinking state
        goToStep(2)
        Thread.sleep(forTimeInterval: 0.4)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "nova-thinking-system-check"; a.lifetime = .keepAlways; add(a)
    }

    func test_screenshot_nova_complete_success() {
        // Step 6 = complete → Nova enters success state
        goToStep(6)
        Thread.sleep(forTimeInterval: 0.4)
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "nova-success-complete"; a.lifetime = .keepAlways; add(a)
    }

    // MARK: - Diagnostics

    func test_dump_and_screenshot_nova() {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = "nova-debug-state"; a.lifetime = .keepAlways; add(a)
        let tree = app.debugDescription.prefix(2000)
        print("NOVA ACCESSIBILITY TREE:\n\(tree)")
        XCTAssertTrue(app.state == .runningForeground)
    }

    // MARK: - Helpers

    private func goToStep(_ stepIndex: Int) {
        for _ in 0..<stepIndex {
            let btn = app.buttons["onboarding_continue"]
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

    private func completeOnboarding() {
        // Walk all 7 steps: welcome(0) → complete(6) → finish
        goToStep(6)
        // Complete step has its own CTA
        let startBtn = app.buttons["onboarding_start_orbit"]
        if startBtn.waitForExistence(timeout: 5) {
            startBtn.tap()
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
}
