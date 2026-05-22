import SwiftUI

// Shared layout helpers used by all step config views.
extension View {
    @ViewBuilder
    func configRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OSpacing.xs) {
            Text(label)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)
            content()
        }
    }

    var privacyNote: some View {
        HStack(spacing: OSpacing.xs) {
            Image(systemName: "lock.shield")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.oTextTertiary)
            Text("This step runs locally. No data leaves your device.")
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
        }
        .padding(.top, OSpacing.sm)
    }
}
