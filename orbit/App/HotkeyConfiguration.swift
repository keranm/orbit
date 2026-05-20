import Foundation
import Carbon.HIToolbox
import AppKit

/// Represents a global keyboard shortcut as Carbon keyCode + modifier flags.
///
/// Carbon modifier flags (for RegisterEventHotKey) differ from NSEvent modifier flags.
/// Conversion is explicit via `carbonModifiers(from:)`.
struct HotkeyConfiguration: Codable, Equatable {

    // Carbon key code — matches kVK_* constants in HIToolbox.Events
    let keyCode: UInt32
    // Carbon modifier flags — cmdKey, optionKey, shiftKey, controlKey
    let carbonModifiers: UInt32
    // Human-readable key name (set at record time from NSEvent.characters)
    let keyDisplayName: String

    // MARK: - Defaults

    /// ⌥ ⇧ Space — the default Mini-Chat shortcut
    static let defaultHotkey = HotkeyConfiguration(
        keyCode: UInt32(kVK_Space),
        carbonModifiers: UInt32(optionKey | shiftKey),
        keyDisplayName: "Space"
    )

    // MARK: - Display

    /// e.g. "⌥ Space" or "⌘ ⇧ K"
    var displayString: String {
        modifierSymbols + keyDisplayName
    }

    private var modifierSymbols: String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s.isEmpty ? "" : s + " "
    }

    // MARK: - Validation

    /// A valid shortcut must have at least one modifier key to avoid conflicts.
    var isValid: Bool { carbonModifiers != 0 }

    // MARK: - Conversion helpers

    /// Converts NSEvent.ModifierFlags to Carbon modifier flags.
    static func carbonModifiers(from nsModifiers: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if nsModifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if nsModifiers.contains(.option)  { carbon |= UInt32(optionKey) }
        if nsModifiers.contains(.shift)   { carbon |= UInt32(shiftKey) }
        if nsModifiers.contains(.control) { carbon |= UInt32(controlKey) }
        return carbon
    }

    /// Derives a display name for a key from an NSEvent.
    static func keyDisplayName(from event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space:             return "Space"
        case kVK_Return:            return "Return"
        case kVK_Tab:               return "Tab"
        case kVK_Delete:            return "⌫"
        case kVK_Escape:            return "Esc"
        case kVK_UpArrow:           return "↑"
        case kVK_DownArrow:         return "↓"
        case kVK_LeftArrow:         return "←"
        case kVK_RightArrow:        return "→"
        case kVK_F1:                return "F1"
        case kVK_F2:                return "F2"
        case kVK_F3:                return "F3"
        case kVK_F4:                return "F4"
        case kVK_F5:                return "F5"
        case kVK_F6:                return "F6"
        case kVK_F7:                return "F7"
        case kVK_F8:                return "F8"
        case kVK_F9:                return "F9"
        case kVK_F10:               return "F10"
        case kVK_F11:               return "F11"
        case kVK_F12:               return "F12"
        default:
            // Use the character produced (unshifted) for letter/symbol keys
            let chars = event.charactersIgnoringModifiers ?? ""
            return chars.uppercased().isEmpty ? "(\(event.keyCode))" : chars.uppercased()
        }
    }
}

// MARK: - Persistence

extension HotkeyConfiguration {
    private static let userDefaultsKey = "miniChatHotkeyConfiguration"

    static func load() -> HotkeyConfiguration {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let config = try? JSONDecoder().decode(HotkeyConfiguration.self, from: data) else {
            return .defaultHotkey
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.userDefaultsKey)
        }
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
