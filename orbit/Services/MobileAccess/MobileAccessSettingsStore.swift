import Foundation
import AppKit

@Observable
@MainActor
final class MobileAccessSettingsStore {
    private(set) var settings: MobileAccessSettings

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let enabled = defaults.bool(forKey: Self.enabledKey)
        let displayName = defaults.string(forKey: Self.displayNameKey)
            ?? Host.current().localizedName ?? "My Mac"
        let allowPairing = defaults.object(forKey: Self.allowPairingKey) as? Bool ?? true
        settings = MobileAccessSettings(
            isEnabled: enabled,
            macDisplayName: String(displayName.prefix(40)),
            allowPairing: allowPairing
        )
    }

    func setEnabled(_ enabled: Bool) {
        settings.isEnabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
    }

    func setMacDisplayName(_ name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
        guard !trimmed.isEmpty else { return }
        settings.macDisplayName = trimmed
        defaults.set(trimmed, forKey: Self.displayNameKey)
    }

    func reset() {
        setEnabled(false)
        setMacDisplayName(Host.current().localizedName ?? "My Mac")
        settings.allowPairing = true
        defaults.set(true, forKey: Self.allowPairingKey)
    }

    // MARK: - Keys

    private static let enabledKey = "mobileAccessEnabled"
    private static let displayNameKey = "mobileAccessDisplayName"
    private static let allowPairingKey = "mobileAccessAllowPairing"
}
