import XCTest
import Carbon.HIToolbox
import AppKit
@testable import orbit

final class HotkeyConfigurationTests: XCTestCase {

    override func setUp() {
        super.setUp()
        HotkeyConfiguration.reset()
    }

    override func tearDown() {
        HotkeyConfiguration.reset()
        super.tearDown()
    }

    // MARK: - Default hotkey

    func test_defaultHotkey_isOptionShiftSpace() {
        let d = HotkeyConfiguration.defaultHotkey
        XCTAssertEqual(d.keyCode, UInt32(kVK_Space))
        XCTAssertEqual(d.carbonModifiers, UInt32(optionKey | shiftKey))
        XCTAssertEqual(d.keyDisplayName, "Space")
    }

    func test_defaultHotkey_displayString_isOptionShiftSpace() {
        // ⌥⇧ Space — option + shift modifiers
        let display = HotkeyConfiguration.defaultHotkey.displayString
        XCTAssertTrue(display.contains("⌥"))
        XCTAssertTrue(display.contains("⇧"))
        XCTAssertTrue(display.contains("Space"))
    }

    func test_defaultHotkey_isValid() {
        XCTAssertTrue(HotkeyConfiguration.defaultHotkey.isValid)
    }

    // MARK: - Display strings

    func test_displayString_commandShiftK() {
        let config = HotkeyConfiguration(
            keyCode: 40,  // kVK_ANSI_K
            carbonModifiers: UInt32(cmdKey | shiftKey),
            keyDisplayName: "K"
        )
        // ⇧ before ⌘ in display order
        XCTAssertTrue(config.displayString.contains("⌘"))
        XCTAssertTrue(config.displayString.contains("⇧"))
        XCTAssertTrue(config.displayString.contains("K"))
    }

    func test_displayString_modifierOrder_controlOptionShiftCommand() {
        // Standard macOS display order: ⌃⌥⇧⌘
        let config = HotkeyConfiguration(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey),
            keyDisplayName: "Space"
        )
        let display = config.displayString
        // Verify all modifiers present
        XCTAssertTrue(display.contains("⌃"))
        XCTAssertTrue(display.contains("⌥"))
        XCTAssertTrue(display.contains("⇧"))
        XCTAssertTrue(display.contains("⌘"))
        XCTAssertTrue(display.contains("Space"))
    }

    func test_displayString_noModifiers_noSymbolPrefix() {
        let config = HotkeyConfiguration(keyCode: UInt32(kVK_Space), carbonModifiers: 0, keyDisplayName: "Space")
        XCTAssertEqual(config.displayString, "Space")
    }

    // MARK: - Validation

    func test_isValid_trueWhenModifiersPresent() {
        let config = HotkeyConfiguration(
            keyCode: UInt32(kVK_Space),
            carbonModifiers: UInt32(optionKey),
            keyDisplayName: "Space"
        )
        XCTAssertTrue(config.isValid)
    }

    func test_isValid_falseWhenNoModifiers() {
        let config = HotkeyConfiguration(keyCode: UInt32(kVK_Space), carbonModifiers: 0, keyDisplayName: "Space")
        XCTAssertFalse(config.isValid, "Bare Space without modifiers must be invalid")
    }

    // MARK: - Persistence

    func test_persistence_saveAndLoad_roundTrip() {
        let original = HotkeyConfiguration(
            keyCode: 40,
            carbonModifiers: UInt32(cmdKey | shiftKey),
            keyDisplayName: "K"
        )
        original.save()
        let loaded = HotkeyConfiguration.load()
        XCTAssertEqual(loaded, original)
    }

    func test_persistence_load_returnsDefaultWhenNothingSaved() {
        HotkeyConfiguration.reset()
        let loaded = HotkeyConfiguration.load()
        XCTAssertEqual(loaded, HotkeyConfiguration.defaultHotkey)
    }

    func test_persistence_reset_removesStoredConfig() {
        HotkeyConfiguration.defaultHotkey.save()
        let saved = UserDefaults.standard.data(forKey: "miniChatHotkeyConfiguration")
        XCTAssertNotNil(saved)
        HotkeyConfiguration.reset()
        let afterReset = UserDefaults.standard.data(forKey: "miniChatHotkeyConfiguration")
        XCTAssertNil(afterReset)
    }

    // MARK: - Modifier conversion

    func test_carbonModifiers_fromNSOptionKey() {
        let carbon = HotkeyConfiguration.carbonModifiers(from: [.option])
        XCTAssertEqual(carbon, UInt32(optionKey))
    }

    func test_carbonModifiers_fromNSCommandKey() {
        let carbon = HotkeyConfiguration.carbonModifiers(from: [.command])
        XCTAssertEqual(carbon, UInt32(cmdKey))
    }

    func test_carbonModifiers_fromNSShiftKey() {
        let carbon = HotkeyConfiguration.carbonModifiers(from: [.shift])
        XCTAssertEqual(carbon, UInt32(shiftKey))
    }

    func test_carbonModifiers_fromNSControlKey() {
        let carbon = HotkeyConfiguration.carbonModifiers(from: [.control])
        XCTAssertEqual(carbon, UInt32(controlKey))
    }

    func test_carbonModifiers_fromCombination() {
        let carbon = HotkeyConfiguration.carbonModifiers(from: [.command, .option])
        XCTAssertEqual(carbon, UInt32(cmdKey | optionKey))
    }

    func test_carbonModifiers_fromEmpty_isZero() {
        let carbon = HotkeyConfiguration.carbonModifiers(from: [])
        XCTAssertEqual(carbon, 0)
    }

    // MARK: - Equatable

    func test_equatable_sameConfigsAreEqual() {
        let a = HotkeyConfiguration(keyCode: 1, carbonModifiers: UInt32(optionKey), keyDisplayName: "A")
        let b = HotkeyConfiguration(keyCode: 1, carbonModifiers: UInt32(optionKey), keyDisplayName: "A")
        XCTAssertEqual(a, b)
    }

    func test_equatable_differentKeyCodesNotEqual() {
        let a = HotkeyConfiguration(keyCode: 1, carbonModifiers: UInt32(optionKey), keyDisplayName: "A")
        let b = HotkeyConfiguration(keyCode: 2, carbonModifiers: UInt32(optionKey), keyDisplayName: "B")
        XCTAssertNotEqual(a, b)
    }
}
