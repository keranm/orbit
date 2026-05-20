import SwiftUI

struct PrivacySection: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingGroup {
                privacyRow(
                    icon: "lock.shield.fill",
                    iconColor: Color.oSuccessGreen,
                    title: "Conversations stay on this Mac",
                    detail: "Your chat history is never uploaded to any server."
                )
                Divider().padding(.leading, OSpacing.xl)
                privacyRow(
                    icon: "cpu",
                    iconColor: Color.oAccent,
                    title: "AI runs locally",
                    detail: "Inference happens on your device. No cloud API is used for chat."
                )
                Divider().padding(.leading, OSpacing.xl)
                privacyRow(
                    icon: "network",
                    iconColor: Color.oMeshTeal,
                    title: "Network usage",
                    detail: "Model downloads require internet. Mesh features use the local network."
                )
                Divider().padding(.leading, OSpacing.xl)
                privacyRow(
                    icon: "chart.bar.xaxis",
                    iconColor: Color.oTextTertiary,
                    title: "No analytics",
                    detail: "Orbit doesn't track usage, sessions, or interactions."
                )
            }

            sectionLabel("Runtime status")

            settingGroup {
                HStack(spacing: OSpacing.sm) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusDescription)
                        .font(.oBody)
                        .foregroundStyle(Color.oTextPrimary)
                    Spacer()
                }
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, OSpacing.sm)
            }
        }
    }

    // MARK: - Helpers

    private var statusColor: Color {
        switch appState.runtimeStatus {
        case .ready:   return Color.oSuccessGreen
        case .offline: return Color.oWarningAmber
        default:       return Color.oTextTertiary
        }
    }

    private var statusDescription: String {
        switch appState.runtimeStatus {
        case .ready:             return "AI is running privately on this Mac"
        case .starting:          return "AI is starting…"
        case .offline:           return "AI runtime is paused"
        case .notInstalled:      return "AI runtime not installed"
        case .noModelConfigured: return "No model configured"
        case .stopping:          return "AI is stopping…"
        case .error:             return "An error occurred"
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.oMicroMed)
            .foregroundStyle(Color.oTextTertiary)
            .padding(.horizontal, OSpacing.md)
            .padding(.top, OSpacing.lg)
            .padding(.bottom, OSpacing.xs)
    }

    private func settingGroup<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(Color.oSurface)
            .clipShape(RoundedRectangle(cornerRadius: ORadius.lg))
            .overlay(RoundedRectangle(cornerRadius: ORadius.lg).stroke(Color.oDivider, lineWidth: 0.5))
    }

    private func privacyRow(icon: String, iconColor: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: OSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(iconColor)
                .frame(width: 22)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
                Text(detail)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextSecondary)
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }
}
