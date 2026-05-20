import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable, Identifiable {
        case general  = "General"
        case models   = "Models"
        case privacy  = "Privacy"
        case mesh     = "Mesh"
        case reset    = "Reset"
        case about    = "About"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general:  return "gearshape"
            case .models:   return "square.stack"
            case .privacy:  return "lock.shield"
            case .mesh:     return "network"
            case .reset:    return "arrow.counterclockwise"
            case .about:    return "info.circle"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 200)

            Divider()

            settingsDetail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

            Divider()
            privacyAtAGlancePanel
                .frame(width: 240)
        }
        .background(Color.oBackground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("settings_view")
    }

    // MARK: - Settings sub-nav

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
                .font(.oTitle2)
                .foregroundStyle(Color.oTextPrimary)
                .padding(.horizontal, OSpacing.md)
                .padding(.top, OSpacing.xl)
                .padding(.bottom, OSpacing.xs)

            Text("Configure Orbit to work the way you want.")
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, OSpacing.md)
                .padding(.bottom, OSpacing.md)

            ForEach(SettingsSection.allCases) { section in
                sidebarRow(section)
            }

            Spacer()
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func sidebarRow(_ section: SettingsSection) -> some View {
        let isSelected = selectedSection == section
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: OSpacing.sm) {
                Image(systemName: section.icon)
                    .font(.system(size: 13, weight: .regular))
                    .frame(width: 16)
                    .foregroundStyle(isSelected ? Color.oAccent : Color.oTextSecondary)

                Text(section.rawValue)
                    .font(.oBody)
                    .foregroundStyle(isSelected ? Color.oAccent : Color.oTextPrimary)

                Spacer()
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ORadius.md)
                    .fill(isSelected ? Color.oSidebarSelected : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, OSpacing.xs)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("settings_nav_\(section.rawValue.lowercased())")
    }

    // MARK: - Settings detail

    private var settingsDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(selectedSection.rawValue)
                    .font(.oTitle2)
                    .foregroundStyle(Color.oTextPrimary)
                    .padding(.bottom, OSpacing.md)

                switch selectedSection {
                case .general:  GeneralSection()
                case .models:   ModelsSection()
                case .privacy:  PrivacySection()
                case .mesh:     MeshSection()
                case .reset:    ResetSection()
                case .about:    AboutSection()
                }

                Spacer(minLength: OSpacing.xl)
            }
            .padding(OSpacing.xl)
        }
    }

    // MARK: - Privacy at a Glance panel

    private var privacyAtAGlancePanel: some View {
        VStack(alignment: .leading, spacing: OSpacing.lg) {
            HStack(spacing: OSpacing.sm) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(Color.oAccent)
                Text("Privacy at a glance")
                    .font(.oBodyMedium)
                    .foregroundStyle(Color.oTextPrimary)
            }

            VStack(alignment: .leading, spacing: OSpacing.sm) {
                privacyBullet(icon: "checkmark.circle.fill", text: "No cloud accounts")
                privacyBullet(icon: "checkmark.circle.fill", text: "Your data stays on your devices")
                privacyBullet(icon: "checkmark.circle.fill", text: "No usage analytics")
                privacyBullet(icon: "checkmark.circle.fill", text: "Private local mesh by default")
            }

            Divider()

            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("Runtime")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextTertiary)

                HStack(spacing: OSpacing.xs) {
                    Circle()
                        .fill(runtimeDotColor)
                        .frame(width: 7, height: 7)
                    Text(runtimeStatusText)
                        .font(.oCaption)
                        .foregroundStyle(Color.oTextPrimary)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: OSpacing.xs) {
                Text("Need help?")
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextTertiary)

                Button {
                    NSWorkspace.shared.open(URL(string: "https://github.com/Mesh-LLM/mesh-llm")!)
                } label: {
                    Text("Documentation")
                        .font(.oCaption)
                        .foregroundStyle(Color.oAccent)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(OSpacing.md)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var runtimeDotColor: Color {
        switch appState.runtimeStatus {
        case .ready:   return Color.oSuccessGreen
        case .offline, .error: return Color.oWarningAmber
        default:       return Color.oTextTertiary
        }
    }

    private var runtimeStatusText: String {
        switch appState.runtimeStatus {
        case .ready:             return "Running on this Mac"
        case .offline:           return "Paused"
        case .starting:          return "Starting…"
        case .notInstalled:      return "Not installed"
        case .noModelConfigured: return "No model"
        default:                 return "Unknown"
        }
    }

    private func privacyBullet(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: OSpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(Color.oSuccessGreen)
                .padding(.top, 2)

            Text(text)
                .font(.oCaption)
                .foregroundStyle(Color.oTextSecondary)
        }
    }
}

#Preview {
    SettingsView()
        .environment(AppState())
        .frame(width: 860, height: 600)
}
