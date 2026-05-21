import SwiftUI

struct PromptEditorMetricsView: View {
    let characterCount: Int
    let usageCount: Int
    let tokenEstimate: Int
    let variableCount: Int

    private let maxChars: Double = 4000

    var body: some View {
        VStack(alignment: .leading, spacing: OSpacing.sm) {
            Text("Metrics")
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)

            // Character progress bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Characters")
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextTertiary)
                    Spacer()
                    Text("\(characterCount) / \(Int(maxChars))")
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                        .monospacedDigit()
                }

                ProgressView(value: min(Double(characterCount), maxChars), total: maxChars)
                    .tint(fillColor)
            }

            // Usage count tile
            HStack(spacing: OSpacing.md) {
                metricTile(title: "Usage", value: "\(usageCount)", icon: "number")
                metricTile(title: "Tokens", value: "~\(tokenEstimate)", icon: "doc.text")
                metricTile(title: "Variables", value: "\(variableCount)", icon: "tag")
            }
        }
    }

    private var fillColor: Color {
        let ratio = Double(characterCount) / maxChars
        if ratio < 0.6 { return Color.oAccent }
        if ratio < 0.85 { return Color.oWarningAmber }
        return Color.red
    }

    private func metricTile(title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.oTextTertiary)

            Text(value)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextPrimary)
                .monospacedDigit()

            Text(title)
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(Color.oSurfaceSecondary)
        )
    }
}
