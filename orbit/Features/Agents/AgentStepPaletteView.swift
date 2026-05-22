import SwiftUI

struct AgentStepPaletteView: View {
    let onAdd: (StepType) -> Void

    @State private var hoveredType: StepType?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            paletteHeader

            Divider()

            ScrollView {
                VStack(spacing: OSpacing.xs) {
                    ForEach(StepType.allCases, id: \.self) { type in
                        paletteTile(type)
                    }
                }
                .padding(OSpacing.sm)
            }
        }
        .background(Color.oSurface)
    }

    private var paletteHeader: some View {
        Text("Add step")
            .font(.oCaptionMed)
            .foregroundStyle(Color.oTextSecondary)
            .padding(.horizontal, OSpacing.md)
            .padding(.vertical, OSpacing.sm)
    }

    private func paletteTile(_ type: StepType) -> some View {
        Button {
            onAdd(type)
        } label: {
            HStack(spacing: OSpacing.sm) {
                Image(systemName: type.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tileIconColor(type))
                    .frame(width: 24, height: 24)
                    .background(tileIconBackground(type))
                    .clipShape(RoundedRectangle(cornerRadius: ORadius.sm))

                VStack(alignment: .leading, spacing: 1) {
                    Text(type.label)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextPrimary)
                    Text(type.subtitle)
                        .font(.oMicro)
                        .foregroundStyle(Color.oTextTertiary)
                }

                Spacer()
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, OSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: ORadius.sm)
                    .fill(hoveredType == type ? Color.oAccentSoft : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: ORadius.sm))
        }
        .buttonStyle(.plain)
        .onHover { over in hoveredType = over ? type : nil }
        .accessibilityLabel("Add \(type.label) step")
        .accessibilityHint(type.subtitle)
    }

    private func tileIconColor(_ type: StepType) -> Color {
        switch type {
        case .readMail:      return Color.oAccent
        case .readCalendar:  return Color.oMeshTeal
        case .readReminders: return Color.oSuccessGreen
        case .readFiles:     return Color.oWarningAmber
        case .readRSS:       return Color.oAccent
        case .think:         return Color.oAccent
        case .condition:     return Color.oWarningAmber
        case .output:        return Color.oSuccessGreen
        }
    }

    private func tileIconBackground(_ type: StepType) -> Color {
        tileIconColor(type).opacity(0.12)
    }
}
