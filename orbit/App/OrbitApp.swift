import SwiftUI
import SwiftData

// macOS 26 (Xcode 26.5): any modifier or wrapper beyond .environment/.frame applied
// to the WindowGroup content causes app.windows = 0 in XCUITest. The only safe
// approach is to keep MainWindowView() as the *only* direct WindowGroup content
// and handle onboarding routing inside MainWindowView.body.
@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(OrbitAppDelegate.self) private var appDelegate
    @State private var appState = AppState()

    /// Shared ModelContainer — created once, reused by both the main UI
    /// and the Mini-Chat overlay (which writes chats back into SwiftData).
    static let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Chat.self, Message.self, PromptTemplate.self, PromptVariable.self, PromptVersion.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    init() {
        if CommandLine.arguments.contains("--reset-onboarding") {
            UserDefaults.standard.set(false, forKey: "hasCompletedOnboarding")
        }
        if CommandLine.arguments.contains("--skip-onboarding") {
            UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        }
    }

    var body: some Scene {
        // ── Main application window ──
        WindowGroup {
            MainWindowView()
                .environment(appState)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    // Expose AppState to components outside the SwiftUI hierarchy
                    AppState.current = appState

                    if CommandLine.arguments.contains("--mock-runtime") {
                        appState.runtimeManager.enterMockReadyState()
                    } else {
                        await appState.runtimeManager.detectInstall()
                        // Restore mesh join config from previous session
                        appState.runtimeManager.restoreMeshConfigIfNeeded()
                        // Auto-start: if a model is configured and the runtime
                        // isn't already running, start it immediately. The sidebar
                        // status indicator communicates progress — the user should
                        // never see the "AI is paused" screen on a normal launch.
                        if appState.runtimeManager.status == .offline {
                            Task { await appState.runtimeManager.start() }
                        }
                    }

                    // Wire Mini-Chat overlay with a shared ModelContext so conversations
                    // created in Mini-Chat appear in the main app sidebar automatically.
                    let context = ModelContext(Self.modelContainer)
                    NovaOverlayViewController.shared.configure(modelContext: context)

                    // Start global hotkeys (skip in UI test environments)
                    if !CommandLine.arguments.contains("--mock-runtime") {
                        MiniChatHotkeyManager.shared.start()
                        ProModeHotkeyManager.shared.start()
                    }
                }
        }
        .modelContainer(Self.modelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { appState.route = .newChat }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .help) {}
        }

        // ── Menu bar presence ──
        // Keeps Orbit alive in the background when the main window is closed.
        // The Nova outline icon provides ambient system presence without
        // requiring the main window to be open.
        MenuBarExtra {
            OrbitMenuBarView()
                .environment(appState)
        } label: {
            // Multi-resolution asset: @1x=18px @2x=36px @3x=54px.
            // Template rendering: black pixels → foreground colour, white → transparent.
            // Adapts automatically to light/dark menu bars.
            Image("NovaMenuBar")
                .renderingMode(.template)
                .accessibilityLabel("Orbit")
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - App delegate

/// Keeps Orbit alive when the main window is closed so the menu bar presence
/// and global Mini-Chat shortcut continue to work in the background.
final class OrbitAppDelegate: NSObject, NSApplicationDelegate {

    /// Returning false prevents Orbit from quitting when the last window is closed.
    /// Cmd+Q still terminates the app normally.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock click with no visible windows → restore the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            sender.windows
                .first(where: { !($0 is NSPanel) })?
                .makeKeyAndOrderFront(nil)
        }
        return true
    }
}
