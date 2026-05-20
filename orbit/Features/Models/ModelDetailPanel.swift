import SwiftUI

/// Side panel shown when the user selects a model from the installed list.
struct ModelDetailPanel: View {
    let model: InstalledModelEntry
    let isActiveModel: Bool
    let onSetActive: () -> Void
    let onRemove: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Model Info")
                    .font(.oTitle3)
                    .foregroundStyle(Color.oTextPrimary)

                Spacer()

                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.oTextSecondary)
                        .padding(6)
                        .background(Circle().fill(Color.oSurfaceSecondary))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close model info")
            }
            .padding(OSpacing.lg)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: OSpacing.lg) {

                    // Model icon + name
                    HStack(spacing: OSpacing.md) {
                        ZStack {
                            RoundedRectangle(cornerRadius: ORadius.md)
                                .fill(Color.oAccentSoft)
                                .frame(width: 44, height: 44)
                            Image(systemName: "cpu")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Color.oAccent)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.displayName)
                                .font(.oTitle3)
                                .foregroundStyle(Color.oTextPrimary)
                                .lineLimit(2)

                            if isActiveModel {
                                HStack(spacing: OSpacing.xs) {
                                    Circle()
                                        .fill(Color.oSuccessGreen)
                                        .frame(width: 6, height: 6)
                                    Text("Active model")
                                        .font(.oCaption)
                                        .foregroundStyle(Color.oSuccessGreen)
                                }
                            }
                        }
                    }

                    // Metadata rows
                    VStack(spacing: 0) {
                        if let size = model.size {
                            metaRow(label: "Size", value: size)
                            Divider().padding(.leading, OSpacing.lg)
                        }
                        if let type = model.typeBadge {
                            metaRow(label: "Format", value: type)
                            Divider().padding(.leading, OSpacing.lg)
                        }
                        if let ref = model.ref {
                            metaRow(label: "Source", value: refDisplayName(ref))
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.lg)
                            .fill(Color.oSurfaceSecondary)
                    )

                    // Path (shown if available)
                    if let p = model.path, !p.isEmpty {
                        VStack(alignment: .leading, spacing: OSpacing.xs) {
                            Text("Location")
                                .font(.oCaptionMed)
                                .foregroundStyle(Color.oTextTertiary)
                            Text(URL(fileURLWithPath: p).lastPathComponent)
                                .font(.oCaption)
                                .foregroundStyle(Color.oTextSecondary)
                                .lineSpacing(3)
                        }
                    }

                    // Privacy note
                    HStack(spacing: OSpacing.sm) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.oAccent)
                        Text("Runs entirely on this Mac — your data stays private")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextSecondary)
                    }
                    .padding(OSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: ORadius.md)
                            .fill(Color.oAccentSoft)
                    )

                    // Actions
                    VStack(spacing: OSpacing.sm) {
                        if !isActiveModel {
                            Button {
                                onSetActive()
                            } label: {
                                HStack {
                                    Spacer()
                                    Text("Use this model")
                                        .font(.oBodyMedium)
                                        .foregroundStyle(.white)
                                    Spacer()
                                }
                                .padding(.vertical, OSpacing.sm)
                                .background(
                                    RoundedRectangle(cornerRadius: ORadius.pill)
                                        .fill(Color.oAccent)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Set \(model.displayName) as active model")
                        }

                        Button {
                            onRemove()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Remove model")
                                    .font(.oCaption)
                                    .foregroundStyle(Color.oTextSecondary)
                                Spacer()
                            }
                            .padding(.vertical, OSpacing.sm)
                            .background(
                                RoundedRectangle(cornerRadius: ORadius.pill)
                                    .fill(Color.oSurfaceSecondary)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(model.displayName)")
                    }
                }
                .padding(OSpacing.lg)
            }
        }
        .background(Color.oSurface)
        .frame(width: 280)
    }

    // MARK: - Helpers

    private func metaRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.oCaption)
                .foregroundStyle(Color.oTextTertiary)
            Spacer()
            Text(value)
                .font(.oCaptionMed)
                .foregroundStyle(Color.oTextSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private func refDisplayName(_ ref: String) -> String {
        // Show just "owner/repo" part for readability
        let parts = ref.components(separatedBy: "@")
        return parts.first ?? ref
    }
}
