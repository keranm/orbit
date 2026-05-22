import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    // Hover tracking avoids per-row @State structs.
    @State private var hoveredRoute: AppRoute?

    // Icon column width shared by nav items and the status footer dot.
    private let iconWidth: CGFloat = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            navList
                .padding(.top, OSpacing.xl)   // clears floating traffic lights

            Spacer(minLength: 0)

            Divider()
                .padding(.horizontal, OSpacing.sm)

            meshStatusFooter
                .padding(.horizontal, OSpacing.xs)
                .padding(.vertical, OSpacing.sm)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Nav list (flat, no section headers)

    private var navList: some View {
        VStack(alignment: .leading, spacing: OSpacing.xxs) {
            navItem(.newChat, icon: "square.and.pencil", label: "New Chat")

            if appState.isProMode {
                navItem(.dashboard,  icon: "chart.bar.fill",      label: "Mesh Dashboard")
                navItem(.coding,     icon: "chevron.left.forwardslash.chevron.right", label: "Code")
                navItem(.playground, icon: "flask.fill",          label: "Playground")
            }

            navItem(.prompts,  icon: "sparkles",     label: "Prompts")
            navItem(.models,   icon: "square.stack", label: "Models")
            navItem(.settings, icon: "gearshape",    label: "Settings")
        }
        .padding(.horizontal, OSpacing.xs)
    }

    // MARK: - Runtime status footer

    private var meshStatusFooter: some View {
        Group {
            switch appState.runtimeStatus {
            case .offline:
                Button {
                    Task { await appState.runtimeManager.start() }
                } label: {
                    statusFooterContent
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("AI is paused. Tap to start.")
            default:
                statusFooterContent
            }
        }
    }

    private var statusFooterContent: some View {
        VStack(alignment: .leading, spacing: OSpacing.xxs) {
            // Row 1: dot (in icon column) + status label
            HStack(spacing: OSpacing.sm) {
                // Dot sits in the same fixed-width column as nav icons.
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                    .frame(width: iconWidth, alignment: .center)

                Text(statusLabel)
                    .font(.oCaptionMed)
                    .foregroundStyle(Color.oTextPrimary)

                Spacer()

                if case .offline = appState.runtimeStatus {
                    Text("Start")
                        .font(.oMicroMed)
                        .foregroundStyle(Color.oAccent)
                }
            }
            .padding(.horizontal, OSpacing.sm)

            // Row 2: subtitle indented to align with label text column.
            Text(statusSubtitle)
                .font(.oMicro)
                .foregroundStyle(Color.oTextTertiary)
                .padding(.leading, OSpacing.sm + iconWidth + OSpacing.sm)
        }
    }

    // MARK: - Nav item helper

    private func navItem(_ route: AppRoute, icon: String, label: String) -> some View {
        let isSelected = appState.route == route
        let isHovered  = hoveredRoute == route

        return Button {
            appState.route = route
        } label: {
            HStack(spacing: OSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13.5, weight: .regular))
                    .frame(width: iconWidth, alignment: .center)
                    .foregroundStyle(isSelected ? Color.oAccent : Color.oTextSecondary)

                Text(label)
                    .font(.oBody)
                    .foregroundStyle(isSelected ? Color.oAccent : Color.oTextPrimary)

                Spacer()
            }
            .padding(.horizontal, OSpacing.sm)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: ORadius.md)
                    .fill(
                        isSelected ? Color.oSidebarSelected :
                        isHovered  ? Color.oSurfaceSecondary : Color.clear
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: ORadius.md))
        }
        .buttonStyle(.plain)
        .onHover { over in hoveredRoute = over ? route : nil }
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    // MARK: - Status copy

    private var statusDotColor: Color {
        switch appState.runtimeStatus {
        case .ready:
            switch appState.runtimeManager.meshConnectionState {
            case .connectedPublic:  return Color.oWarningAmber
            case .connectedPrivate: return Color.oMeshTeal
            default:                return Color.oSuccessGreen
            }
        case .starting:                                     return Color.oWarningAmber
        case .offline, .error:                              return Color.oWarningAmber
        case .notInstalled, .noModelConfigured, .stopping:  return Color.oTextTertiary
        }
    }

    private var statusLabel: String {
        switch appState.runtimeStatus {
        case .ready:
            if appState.runtimeManager.activeMeshModel != nil {
                switch appState.runtimeManager.meshConnectionState {
                case .connectedPublic:  return "Active on shared mesh"
                case .connectedPrivate: return "Active on your mesh"
                default:                break
                }
            }
            return "Ready locally"
        case .starting:          return "Starting…"
        case .offline:           return "AI paused"
        case .stopping:          return "Stopping…"
        case .notInstalled:      return "Not installed"
        case .noModelConfigured: return "No model"
        case .error:             return "Error"
        }
    }

    private var statusSubtitle: String {
        // When connected to a mesh, show connection context instead of default
        switch appState.runtimeManager.meshConnectionState {
        case .connectedPrivate(let n):
            return "On your mesh · \(n) \(n == 1 ? "device" : "devices")"
        case .connectedPublic(let n):
            return "Shared mesh · \(n) participants"
        case .connectingPrivate, .connectingPublic:
            return "Connecting to mesh…"
        case .reconnecting:
            return "Reconnecting…"
        default:
            break
        }
        switch appState.runtimeStatus {
        case .ready:             return "Private to this Mac"
        case .starting:          return "Loading your AI…"
        case .offline:           return "Tap to start"
        case .stopping:          return "Shutting down…"
        case .notInstalled:      return "Complete setup to begin"
        case .noModelConfigured: return "Choose a model in Models"
        case .error(let msg):
            let trimmed = msg.prefix(60)
            return trimmed.count < msg.count ? "\(trimmed)…" : msg
        }
    }
}

#Preview {
    SidebarView()
        .environment(AppState())
        .frame(width: 220, height: 600)
}
