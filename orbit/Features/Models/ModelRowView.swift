import SwiftUI

/// A single installed model row in the Local models list.
struct ModelRowView: View {
    let model: InstalledModelEntry
    let isSelected: Bool
    let downloadPhase: ModelService.DownloadPhase?
    let isActiveModel: Bool
    let onSelect: () -> Void
    let onSetActive: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: OSpacing.md) {
            // Model icon
            ZStack {
                RoundedRectangle(cornerRadius: ORadius.sm)
                    .fill(Color.oAccentSoft)
                    .frame(width: 34, height: 34)
                Image(systemName: "cpu")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.oAccent)
            }

            // Name + badges
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: OSpacing.xs) {
                    Text(model.displayName)
                        .font(.oBodyMedium)
                        .foregroundStyle(Color.oTextPrimary)
                        .lineLimit(1)

                    if isActiveModel {
                        Text("Active")
                            .font(.oMicroMed)
                            .foregroundStyle(Color.oAccent)
                            .padding(.horizontal, OSpacing.xs)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.oAccentSoft))
                    }
                }

                HStack(spacing: OSpacing.xs) {
                    if let badge = model.typeBadge {
                        Text(badge)
                            .font(.oMicro)
                            .foregroundStyle(Color.oTextTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.sm)
                                    .fill(Color.oDivider)
                            )
                    }
                    if let size = model.size {
                        Text(size)
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                }
            }

            Spacer()

            // Action buttons (visible on hover or selection)
            if isHovered || isSelected {
                HStack(spacing: OSpacing.xs) {
                    if !isActiveModel {
                        Button {
                            onSetActive()
                        } label: {
                            Text("Use")
                                .font(.oCaption)
                                .foregroundStyle(Color.oAccent)
                                .padding(.horizontal, OSpacing.sm)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: ORadius.sm)
                                        .fill(Color.oAccentSoft)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Set \(model.displayName) as active model")
                    }

                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.oTextTertiary)
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.sm)
                                    .fill(Color.oSurfaceSecondary)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(model.displayName)")
                }
                .transition(.opacity)
            }

            // Info / chevron
            Button {
                onSelect()
            } label: {
                Image(systemName: isSelected ? "chevron.right.circle.fill" : "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? Color.oAccent : Color.oTextTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Close model info" : "Show info for \(model.displayName)")
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: ORadius.md)
                .fill(isSelected ? Color.oAccentSoft : (isHovered ? Color.oSurfaceSecondary : Color.clear))
        )
        .contentShape(RoundedRectangle(cornerRadius: ORadius.md))
        .onHover { isHovered = $0 }
        .onTapGesture { onSelect() }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
        .animation(.easeInOut(duration: 0.12), value: isSelected)
        .accessibilityElement(children: .contain)
    }
}
