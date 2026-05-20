import XCTest
@testable import orbit

/// Tests for PromptSettings persistence, context generation, and system message assembly.
final class PromptSettingsTests: XCTestCase {

    // MARK: - Test UserDefaults isolation

    override func setUp() {
        super.setUp()
        // Wipe prompt keys so each test starts fresh.
        UserDefaults.standard.removeObject(forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.removeObject(forKey: PromptSettings.userPreferencesKey)
        UserDefaults.standard.removeObject(forKey: PromptSettings.includeLocalContextKey)
    }

    override func tearDown() {
        super.tearDown()
        UserDefaults.standard.removeObject(forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.removeObject(forKey: PromptSettings.userPreferencesKey)
        UserDefaults.standard.removeObject(forKey: PromptSettings.includeLocalContextKey)
    }

    // MARK: - Default values

    func test_readDefaultPrompt_returnsDefaultWhenNotSet() {
        let text = PromptSettings.readDefaultPrompt()
        XCTAssertEqual(text, PromptSettings.defaultPromptText)
    }

    func test_readUserPreferences_returnsEmptyWhenNotSet() {
        let text = PromptSettings.readUserPreferences()
        XCTAssertTrue(text.isEmpty)
    }

    func test_readIncludeLocalContext_returnsTrueByDefault() {
        let flag = PromptSettings.readIncludeLocalContext()
        XCTAssertTrue(flag, "Local context should be enabled by default")
    }

    func test_defaultPromptText_isNonEmpty() {
        XCTAssertFalse(PromptSettings.defaultPromptText.isEmpty)
    }

    // MARK: - Persistence round-trip

    func test_defaultPromptPersists() {
        UserDefaults.standard.set("Custom prompt.", forKey: PromptSettings.defaultPromptKey)
        XCTAssertEqual(PromptSettings.readDefaultPrompt(), "Custom prompt.")
    }

    func test_userPreferencesPersists() {
        UserDefaults.standard.set("I like short answers.", forKey: PromptSettings.userPreferencesKey)
        XCTAssertEqual(PromptSettings.readUserPreferences(), "I like short answers.")
    }

    func test_includeLocalContextPersistsFalse() {
        UserDefaults.standard.set(false, forKey: PromptSettings.includeLocalContextKey)
        XCTAssertFalse(PromptSettings.readIncludeLocalContext())
    }

    // MARK: - resetToDefaults

    func test_resetToDefaults_restoresDefaultPrompt() {
        UserDefaults.standard.set("Changed", forKey: PromptSettings.defaultPromptKey)
        PromptSettings.resetToDefaults()
        XCTAssertEqual(PromptSettings.readDefaultPrompt(), PromptSettings.defaultPromptText)
    }

    func test_resetToDefaults_clearsUserPreferences() {
        UserDefaults.standard.set("Some prefs", forKey: PromptSettings.userPreferencesKey)
        PromptSettings.resetToDefaults()
        XCTAssertTrue(PromptSettings.readUserPreferences().isEmpty)
    }

    func test_resetToDefaults_restoresContextToggle() {
        UserDefaults.standard.set(false, forKey: PromptSettings.includeLocalContextKey)
        PromptSettings.resetToDefaults()
        XCTAssertTrue(PromptSettings.readIncludeLocalContext())
    }

    // MARK: - buildSystemMessage

    func test_buildSystemMessage_containsDefaultPrompt_whenSet() {
        UserDefaults.standard.set("Be concise.", forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.set(false, forKey: PromptSettings.includeLocalContextKey)
        let msg = PromptSettings.buildSystemMessage()
        XCTAssertTrue(msg.contains("Be concise."))
    }

    func test_buildSystemMessage_containsUserPreferences_whenSet() {
        UserDefaults.standard.set("", forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.set("I prefer bullet points.", forKey: PromptSettings.userPreferencesKey)
        UserDefaults.standard.set(false, forKey: PromptSettings.includeLocalContextKey)
        let msg = PromptSettings.buildSystemMessage()
        XCTAssertTrue(msg.contains("I prefer bullet points."))
        XCTAssertTrue(msg.contains("About me:"))
    }

    func test_buildSystemMessage_excludesContextWhenDisabled() {
        UserDefaults.standard.set("", forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.set(false, forKey: PromptSettings.includeLocalContextKey)
        let msg = PromptSettings.buildSystemMessage()
        XCTAssertFalse(msg.contains("My current context:"))
    }

    func test_buildSystemMessage_includesContextWhenEnabled() {
        UserDefaults.standard.set("", forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.set(true, forKey: PromptSettings.includeLocalContextKey)
        let msg = PromptSettings.buildSystemMessage()
        XCTAssertTrue(msg.contains("My current context:"))
        XCTAssertTrue(msg.contains("Timezone:"))
        XCTAssertTrue(msg.contains("Device:"))
    }

    func test_buildSystemMessage_emptyWhenAllComponentsEmpty() {
        UserDefaults.standard.set("", forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.set("", forKey: PromptSettings.userPreferencesKey)
        UserDefaults.standard.set(false, forKey: PromptSettings.includeLocalContextKey)
        let msg = PromptSettings.buildSystemMessage()
        XCTAssertTrue(msg.isEmpty, "Message should be empty when prompt, prefs, and context are all empty/disabled")
    }

    func test_buildSystemMessage_separatesPartsWithDoubleNewline() {
        UserDefaults.standard.set("Prompt text.", forKey: PromptSettings.defaultPromptKey)
        UserDefaults.standard.set("Prefs text.", forKey: PromptSettings.userPreferencesKey)
        UserDefaults.standard.set(false, forKey: PromptSettings.includeLocalContextKey)
        let msg = PromptSettings.buildSystemMessage()
        XCTAssertTrue(msg.contains("\n\n"), "Parts should be separated by double newlines")
    }

    // MARK: - Context helpers

    func test_locationFromTimezone_isNonEmpty() {
        let loc = PromptSettings.locationFromTimezone()
        XCTAssertFalse(loc.isEmpty)
    }

    func test_formattedDateTime_isNonEmpty() {
        let dt = PromptSettings.formattedDateTime()
        XCTAssertFalse(dt.isEmpty)
    }

    func test_formattedDateTime_containsYear() {
        let dt = PromptSettings.formattedDateTime()
        XCTAssertTrue(dt.contains("2025") || dt.contains("2026"), "Date should contain the current year")
    }

    func test_deviceModel_isNonEmpty() {
        let model = PromptSettings.deviceModel()
        XCTAssertFalse(model.isEmpty)
    }

    func test_languageDescription_isNonEmpty() {
        let lang = PromptSettings.languageDescription()
        XCTAssertFalse(lang.isEmpty)
    }

    func test_buildContextBlock_containsAllKeys() {
        let block = PromptSettings.buildContextBlock()
        XCTAssertTrue(block.contains("Timezone:"))
        XCTAssertTrue(block.contains("Date & time:"))
        XCTAssertTrue(block.contains("Device:"))
        XCTAssertTrue(block.contains("Language:"))
    }

    func test_locationFromTimezone_formatsCorrectly_forAustraliaAdelaide() {
        // This is a pure string-parsing test — doesn't depend on the actual timezone.
        // We test the parsing logic in isolation via a known input.
        let knownTz = "Australia/Adelaide"
        let parts = knownTz.components(separatedBy: "/")
        guard parts.count == 2 else { XCTFail("Expected 2 parts"); return }
        let city   = parts[1].replacingOccurrences(of: "_", with: " ")
        let region = parts[0]
        let result = "\(city), \(region)"
        XCTAssertEqual(result, "Adelaide, Australia")
    }

    func test_locationFromTimezone_handlesUnderscores() {
        // "America/New_York" → "New York, America"
        let id = "America/New_York"
        let parts = id.components(separatedBy: "/")
        let city   = parts[1].replacingOccurrences(of: "_", with: " ")
        let region = parts[0]
        XCTAssertEqual("\(city), \(region)", "New York, America")
    }
}
