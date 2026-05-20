import SwiftUI

struct GeneralSection: View {
    @Environment(AppState.self) private var appState
    @AppStorage("showModelReasoning") private var showReasoning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Runtime
            settingGroup {
                settingRowWithAction(
                    title: "Active model",
                    detail: activeModelName,
                    actionLabel: "Change",
                    action: { appState.route = .models }
                )
                Divider().padding(.leading, OSpacing.md)
                settingRow(title: "Runtime", detail: runtimeVersion)
            }

            sectionLabel("AI behaviour")

            settingGroup {
                settingRowWithAction(
                    title: "Prompts & context",
                    detail: "Customise how Orbit responds",
                    actionLabel: "Open",
                    action: { appState.route = .prompts }
                )
            }

            sectionLabel("Responses")

            settingGroup {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show model reasoning")
                            .font(.oBody)
                            .foregroundStyle(Color.oTextPrimary)
                        Text("Display thinking steps above the response. Off by default.")
                            .font(.oCaption)
                            .foregroundStyle(Color.oTextTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $showReasoning)
                        .toggleStyle(.switch)
                        .tint(Color.oAccent)
                        .labelsHidden()
                        .accessibilityLabel("Show model reasoning")
                }
                .padding(.horizontal, OSpacing.md)
                .padding(.vertical, OSpacing.sm)
            }

            sectionLabel("Mini-Chat")

            settingGroup {
                MiniChatShortcutRow()
            }

            sectionLabel("Keyboard shortcuts")

            settingGroup {
                shortcutRow(label: "Send message", keys: "Return")
                Divider().padding(.leading, OSpacing.md)
                shortcutRow(label: "New line",     keys: "⇧ Return")
                Divider().padding(.leading, OSpacing.md)
                shortcutRow(label: "New chat",     keys: "⌘ N")
            }
        }
    }

    // MARK: - Helpers

    private var activeModelName: String {
        let installed = appState.runtimeManager.installedModels
        if let ref = appState.activeModelRef,
           let match = installed.first(where: { ($0.ref ?? $0.name) == ref }) {
            return match.displayName
        }
        return installed.first?.displayName ?? "None"
    }

    private var runtimeVersion: String {
        if let ver = appState.runtimeManager.installedVersion { return "v\(ver)" }
        return appState.runtimeStatus == .notInstalled ? "Not installed" : "Unknown"
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

    private func settingRow(title: String, detail: String) -> some View {
        HStack {
            Text(title)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
            Spacer()
            Text(detail)
                .font(.oBody)
                .foregroundStyle(Color.oTextTertiary)
                .lineLimit(1)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private func settingRowWithAction(
        title: String,
        detail: String,
        actionLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.oBody)
                    .foregroundStyle(Color.oTextPrimary)
                Text(detail)
                    .font(.oCaption)
                    .foregroundStyle(Color.oTextTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Button(action: action) {
                Text(actionLabel)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }

    private func shortcutRow(label: String, keys: String) -> some View {
        HStack {
            Text(label)
                .font(.oBody)
                .foregroundStyle(Color.oTextPrimary)
            Spacer()
            Text(keys)
                .font(.oBodyMedium)
                .foregroundStyle(Color.oTextSecondary)
                .padding(.horizontal, OSpacing.sm)
                .padding(.vertical, 3)
                .background(
                    RoundedRectangle(cornerRadius: ORadius.sm)
                        .fill(Color.oSurfaceSecondary)
                        .overlay(RoundedRectangle(cornerRadius: ORadius.sm).stroke(Color.oDivider, lineWidth: 0.5))
                )
        }
        .padding(.horizontal, OSpacing.md)
        .padding(.vertical, OSpacing.sm)
    }
}
