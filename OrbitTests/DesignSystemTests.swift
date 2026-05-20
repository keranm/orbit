import XCTest
import SwiftUI
@testable import orbit

final class DesignSystemTests: XCTestCase {

    // MARK: - OSpacing

    func test_spacing_scale_values() {
        XCTAssertEqual(OSpacing.xxs,  2)
        XCTAssertEqual(OSpacing.xs,   4)
        XCTAssertEqual(OSpacing.sm,   8)
        XCTAssertEqual(OSpacing.md,   16)
        XCTAssertEqual(OSpacing.lg,   24)
        XCTAssertEqual(OSpacing.xl,   32)
        XCTAssertEqual(OSpacing.xxl,  48)
        XCTAssertEqual(OSpacing.xxxl, 64)
    }

    func test_spacing_scale_is_strictly_ascending() {
        let steps: [CGFloat] = [
            OSpacing.xxs, OSpacing.xs, OSpacing.sm, OSpacing.md,
            OSpacing.lg, OSpacing.xl, OSpacing.xxl, OSpacing.xxxl
        ]
        for i in 1..<steps.count {
            XCTAssertGreaterThan(steps[i], steps[i - 1],
                "OSpacing step \(i) must be larger than step \(i-1)")
        }
    }

    // MARK: - ORadius

    func test_radius_scale_values() {
        XCTAssertEqual(ORadius.sm,   6)
        XCTAssertEqual(ORadius.md,   10)
        XCTAssertEqual(ORadius.lg,   14)
        XCTAssertEqual(ORadius.xl,   20)
        XCTAssertEqual(ORadius.pill, 999)
    }

    func test_radius_scale_is_strictly_ascending() {
        let steps: [CGFloat] = [ORadius.sm, ORadius.md, ORadius.lg, ORadius.xl]
        for i in 1..<steps.count {
            XCTAssertGreaterThan(steps[i], steps[i - 1],
                "ORadius step \(i) must be larger than step \(i-1)")
        }
    }

    func test_pill_radius_is_largest() {
        XCTAssertGreaterThan(ORadius.pill, ORadius.xl)
    }

    // MARK: - OColors (resolves without crash)

    func test_color_tokens_resolve() {
        // Verify every token initialises without throwing.
        // Colours are opaque types — we confirm they are non-nil via String description.
        let tokens: [Color] = [
            .oBackground, .oSurface, .oSurfaceSecondary,
            .oAccent, .oAccentSoft, .oAccentMid,
            .oTextPrimary, .oTextSecondary, .oTextTertiary, .oTextInverse,
            .oDivider,
            .oMeshTeal, .oWarningAmber, .oSuccessGreen, .oErrorRed,
            .oSidebarSelected,
            .oOrbCore, .oOrbGlow,
        ]
        for token in tokens {
            let desc = String(describing: token)
            XCTAssertFalse(desc.isEmpty, "Color token should produce a non-empty description")
        }
    }

    func test_accent_is_different_from_background() {
        XCTAssertNotEqual(Color.oAccent, Color.oBackground)
    }

    func test_text_hierarchy_tokens_are_distinct() {
        XCTAssertNotEqual(Color.oTextPrimary,   Color.oTextSecondary)
        XCTAssertNotEqual(Color.oTextSecondary, Color.oTextTertiary)
        XCTAssertNotEqual(Color.oTextPrimary,   Color.oTextTertiary)
    }

    // MARK: - OTypography

    func test_font_tokens_resolve() {
        let fonts: [Font] = [
            .oDisplay, .oLargeTitle,
            .oTitle1, .oTitle2, .oTitle3,
            .oBodyLarge, .oBody, .oBodyMedium,
            .oCaption, .oCaptionMed,
            .oMicro, .oMicroMed,
        ]
        for font in fonts {
            let desc = String(describing: font)
            XCTAssertFalse(desc.isEmpty)
        }
    }
}
