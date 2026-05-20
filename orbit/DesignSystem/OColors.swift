import SwiftUI
import AppKit

// All Orbit color tokens. Reference only these — never hardcode hex values in views.
// Adaptive tokens automatically switch between light and dark mode appearances.
extension Color {

    // MARK: Backgrounds
    static let oBackground       = Color.adaptive(light: "F5F4F2", dark: "1A1A1A")
    static let oSurface          = Color.adaptive(light: "FFFFFF", dark: "242424")
    static let oSurfaceSecondary = Color.adaptive(light: "F2F1EF", dark: "2C2C2E")

    // MARK: Accent
    static let oAccent           = Color.adaptive(light: "4A8FD4", dark: "5A9FE4")
    static let oAccentSoft       = Color.adaptive(light: "EBF3FC", dark: "1A2F45")
    static let oAccentMid        = Color.adaptive(light: "C8DFF5", dark: "2A4060")

    // MARK: Text
    static let oTextPrimary      = Color.adaptive(light: "1A1A1A", dark: "EBEBF5")
    static let oTextSecondary    = Color.adaptive(light: "6B6B6B", dark: "A0A0A8")
    static let oTextTertiary     = Color.adaptive(light: "9E9E9E", dark: "636366")
    static let oTextInverse      = Color.adaptive(light: "FFFFFF", dark: "1A1A1A")

    // MARK: Structural
    static let oDivider          = Color.adaptive(light: "E8E8E6", dark: "383838")

    // MARK: Status (same in both modes)
    static let oMeshTeal         = Color(orbitHex: "2ABFBF")
    static let oWarningAmber     = Color(orbitHex: "F0A030")
    static let oSuccessGreen     = Color(orbitHex: "34A853")
    static let oErrorRed         = Color(orbitHex: "D93025")

    // MARK: Sidebar
    static let oSidebarSelected  = Color.adaptive(light: "E0ECF9", dark: "1C3050")

    // MARK: Orb
    static let oOrbCore          = Color(orbitHex: "7BB8F0")
    static let oOrbGlow          = Color(orbitHex: "B8D8F8")
}

// MARK: - Private helpers

private extension Color {
    /// Adaptive color that switches between light and dark appearances.
    static func adaptive(light lightHex: String, dark darkHex: String) -> Color {
        let lightNS = NSColor(orbitHex: lightHex)
        let darkNS  = NSColor(orbitHex: darkHex)
        return Color(nsColor: NSColor(name: nil) { appearance in
            switch appearance.bestMatch(from: [.aqua, .darkAqua]) {
            case .darkAqua: return darkNS
            default:        return lightNS
            }
        })
    }

    /// Fixed hex color — identical in light and dark mode. Use only for status colors.
    init(orbitHex hex: String) {
        self.init(nsColor: NSColor(orbitHex: hex))
    }
}

private extension NSColor {
    convenience init(orbitHex hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: h).scanHexInt64(&value)
        self.init(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green:   CGFloat((value >> 8)  & 0xFF) / 255,
            blue:    CGFloat(value         & 0xFF) / 255,
            alpha:   1
        )
    }
}
