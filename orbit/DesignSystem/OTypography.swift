import SwiftUI

// Orbit font scale. All use SF Pro (system font) — no custom fonts in V1.
extension Font {

    // MARK: Display
    static let oDisplay     = Font.system(size: 32, weight: .bold)
    static let oLargeTitle  = Font.system(size: 26, weight: .bold)

    // MARK: Title
    static let oTitle1      = Font.system(size: 20, weight: .semibold)
    static let oTitle2      = Font.system(size: 17, weight: .semibold)
    static let oTitle3      = Font.system(size: 15, weight: .semibold)

    // MARK: Body
    static let oBodyLarge   = Font.system(size: 15, weight: .regular)
    static let oBody        = Font.system(size: 14, weight: .regular)
    static let oBodyMedium  = Font.system(size: 14, weight: .medium)

    // MARK: Caption
    static let oCaption     = Font.system(size: 12, weight: .regular)
    static let oCaptionMed  = Font.system(size: 12, weight: .medium)

    // MARK: Micro
    static let oMicro       = Font.system(size: 11, weight: .regular)
    static let oMicroMed    = Font.system(size: 11, weight: .medium)
}
