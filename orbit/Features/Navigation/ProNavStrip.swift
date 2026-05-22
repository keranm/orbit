import SwiftUI

struct ProNavStrip: View {
    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: 80)
            ProNavIcons()
            Spacer(minLength: 0)
            ProNavStatus()
                .padding(.trailing, OSpacing.md)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 20)
    }
}

// MARK: - Nav Icons

private struct ProNavIcons: View {
    @Environment(AppState.self) private var appState
    @State private var hoveredRoute: AppRoute?

    private struct NavItem {
        let route: AppRoute
        let icon: String
        let label: String
    }

    private let items: [NavItem] = [
        NavItem(route: .newChat,    icon: "square.and.pencil",                       label: "Chat"),
        NavItem(route: .dashboard,  icon: "chart.bar.fill",                          label: "Dashboard"),
        NavItem(route: .coding,     icon: "chevron.left.forwardslash.chevron.right", label: "Code"),
        NavItem(route: .playground, icon: "flask.fill",                              label: "Playground"),
        NavItem(route: .prompts,    icon: "sparkles",                                label: "Prompts"),
        NavItem(route: .models,     icon: "square.stack",                            label: "Models"),
        NavItem(route: .settings,   icon: "gearshape",                               label: "Settings"),
    ]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items, id: \.label) { item in
                navButton(item)
            }
        }
    }

    private func navButton(_ item: NavItem) -> some View {
        let isSelected = routeMatches(item.route)
        let isHovered  = hoveredRoute == item.route

        return Button {
            appState.route = item.route
        } label: {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(isSelected ? Color.oAccent : Color.oTextSecondary)
                .frame(width: 20, height: 20)
                .background(
                    isHovered ? Color.oSurfaceSecondary : Color.clear,
                    in: RoundedRectangle(cornerRadius: ORadius.sm)
                )
        }
        .buttonStyle(.plain)
        .onHover { over in hoveredRoute = over ? item.route : nil }
        .help(item.label)
    }

    private func routeMatches(_ route: AppRoute) -> Bool {
        switch (appState.route, route) {
        case (.newChat, .newChat),
             (.chat,    .newChat): return true
        default:                   return appState.route == route
        }
    }
}

// MARK: - Status Badge

private struct ProNavStatus: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: OSpacing.sm) {
            HStack(spacing: OSpacing.xs) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 6, height: 6)
                Text(statusLabel)
                    .font(.oMicro)
                    .foregroundStyle(Color.oTextSecondary)
            }

            Text("PRO")
                .font(.oMicroMed)
                .foregroundStyle(Color.oAccent)
                .padding(.horizontal, OSpacing.xs)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.oAccentSoft))
                .overlay(Capsule().stroke(Color.oAccent.opacity(0.3), lineWidth: 1))
        }
    }

    private var statusDotColor: Color {
        switch appState.runtimeStatus {
        case .ready:    return Color.oSuccessGreen
        case .starting: return Color.oWarningAmber
        default:        return Color.oTextTertiary
        }
    }

    private var statusLabel: String {
        switch appState.runtimeStatus {
        case .ready:             return "Ready locally"
        case .starting:          return "Starting…"
        case .offline:           return "Offline"
        case .stopping:          return "Stopping…"
        case .notInstalled:      return "Not installed"
        case .noModelConfigured: return "No model"
        case .error:             return "Error"
        }
    }
}
