import SwiftUI

/// Menu bar popover content — the primary access point for Orbit when the
/// main window is closed and Orbit is running in the background.
struct OrbitMenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            Button("Open Orbit") { openMainWindow() }
                .keyboardShortcut("o", modifiers: .command)

            Divider()

            Button("New Chat") {
                openMainWindow()
                appState.route = .newChat
            }

            Button(action: { NovaOverlayViewController.shared.toggle() }) {
                HStack {
                    Text("Mini-Chat")
                    Spacer()
                    Text("⌥⇧Space")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            Divider()

            runtimeStatusItem

            Divider()

            Button("Settings") {
                openMainWindow()
                appState.route = .settings
            }

            Divider()

            Button("Quit Orbit") { NSApp.terminate(nil) }
                .keyboardShortcut("q", modifiers: .command)
        }
    }

    // MARK: - Runtime status item

    @ViewBuilder
    private var runtimeStatusItem: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor)
                .frame(width: 7, height: 7)
            Text(statusLabel)
                .foregroundStyle(.secondary)
        }
        .font(.callout)
    }

    private var statusDotColor: Color {
        switch appState.runtimeStatus {
        case .ready:                return Color.oSuccessGreen
        case .starting:             return Color.oWarningAmber
        case .offline, .error:      return Color.oWarningAmber
        default:                    return Color.secondary
        }
    }

    private var statusLabel: String {
        switch appState.runtimeStatus {
        case .ready:             return "Running locally"
        case .starting:          return "Starting…"
        case .offline:           return "AI paused"
        case .stopping:          return "Stopping…"
        case .notInstalled:      return "Not installed"
        case .noModelConfigured: return "No model selected"
        case .error:             return "Error"
        }
    }

    // MARK: - Window management

    private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        // Find the main (non-panel) window and bring it forward.
        // If it was closed, activating the app with no windows triggers
        // applicationShouldHandleReopen which recreates it.
        if let main = NSApp.windows.first(where: { !($0 is NSPanel) }) {
            main.makeKeyAndOrderFront(nil)
        }
    }
}
