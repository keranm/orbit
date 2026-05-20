import SwiftUI

// MARK: - Card

struct OCardModifier: ViewModifier {
    var elevation: Elevation = .low

    enum Elevation { case low, medium }

    func body(content: Content) -> some View {
        content
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
            .shadow(
                color: Color.black.opacity(elevation == .low ? 0.05 : 0.10),
                radius: elevation == .low ? 4 : 10,
                x: 0,
                y: elevation == .low ? 1 : 3
            )
    }
}

// MARK: - Surface (no shadow)

struct OSurfaceModifier: ViewModifier {
    var radius: CGFloat = ORadius.md

    func body(content: Content) -> some View {
        content
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// MARK: - Pill badge

struct OBadgeModifier: ViewModifier {
    var color: Color = Color.oAccentSoft
    var textColor: Color = Color.oAccent

    func body(content: Content) -> some View {
        content
            .font(.oMicroMed)
            .foregroundStyle(textColor)
            .padding(.horizontal, OSpacing.xs)
            .padding(.vertical, OSpacing.xxs)
            .background(
                Capsule().fill(color)
            )
    }
}

// MARK: - View extensions

extension View {
    func oCard(elevation: OCardModifier.Elevation = .low) -> some View {
        modifier(OCardModifier(elevation: elevation))
    }

    func oSurface(radius: CGFloat = ORadius.md) -> some View {
        modifier(OSurfaceModifier(radius: radius))
    }

    func oBadge(color: Color = .oAccentSoft, textColor: Color = .oAccent) -> some View {
        modifier(OBadgeModifier(color: color, textColor: textColor))
    }
}
