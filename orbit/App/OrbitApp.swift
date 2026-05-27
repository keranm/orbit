import SwiftUI
import SwiftData
import Sparkle

// Provides the appcast feed URL to Sparkle so it doesn't need SUFeedURL in Info.plist.
// File-scoped so it outlives any single struct instance.
private final class OrbitSparkleDelegate: NSObject, SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://raw.githubusercontent.com/keranm/orbit-release/main/appcast.xml"
    }
}
private let _sparkleDelegate = OrbitSparkleDelegate()

// macOS 26 (Xcode 26.5): any modifier or wrapper beyond .environment/.frame applied
// to the WindowGroup content causes app.windows = 0 in XCUITest. The only safe
// approach is to keep MainWindowView() as the *only* direct WindowGroup content
// and handle onboarding routing inside MainWindowView.body.
@main
struct OrbitApp: App {
    @NSApplicationDelegateAdaptor(OrbitAppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: _sparkleDelegate,
        userDriverDelegate: nil
    )

    /// Shared ModelContainer — created once, reused by both the main UI
    /// and the Mini-Chat overlay (which writes chats back into SwiftData).
    static let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: Chat.self, Message.self, Agent.self, AgentStep.self, AgentRun.self)
        } catch {
            // Schema evolved between builds — delete the store and start fresh.
            // Chat history is lost but the app stays usable. Production builds
            // should add explicit SwiftData migrations instead.
            NSLog("Orbit: ModelContainer init failed (\(error)). Deleting store and retrying.")
            let fm = FileManager.default
            let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let bundleID = Bundle.main.bundleIdentifier ?? "com.keranmckenzie.orbit"
            let storeDir = appSupport.appendingPathComponent(bundleID)
            if let files = try? fm.contentsOfDirectory(at: storeDir, includingPropertiesForKeys: nil) {
                for file in files where file.lastPathComponent.hasSuffix(".store")
                    || file.lastPathComponent.hasSuffix(".store-shm")
                    || file.lastPathComponent.hasSuffix(".store-wal") {
                    try? fm.removeItem(at: file)
                }
            }
            do {
                return try ModelContainer(for: Chat.self, Message.self, Agent.self, AgentStep.self, AgentRun.self)
            } catch {
                fatalError("Orbit: ModelContainer unrecoverable after store deletion: \(error)")
            }
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
                .frame(minWidth: 1100, minHeight: 700)
                .task {
                    // Expose AppState to components outside the SwiftUI hierarchy
                    AppState.current = appState

                    if CommandLine.arguments.contains("--mock-runtime") {
                        appState.runtimeManager.enterMockReadyState()
                    } else {
                        await appState.runtimeManager.detectInstall()
                        // Restore mesh join config from previous session.
                        await appState.runtimeManager.restoreMeshConfigIfNeeded()
                        // Auto-start is handled by ensureRunning() in appShell.task
                        // (MainWindowView). Starting here as well races with it:
                        // the second start() call cancels the first startupTask while
                        // the first process still holds port 9337, causing the second
                        // process to exit immediately → "AI paused" on every launch.
                        // Auto-restore Mobile Access if it was enabled before closing.
                        // Poll until the runtime is ready (up to 60s) then re-enable.
                        Task {
                            for _ in 0..<60 {
                                if case .ready = appState.runtimeManager.status {
                                    await appState.mobileAccessCoordinator.autoStartIfPreviouslyEnabled()
                                    return
                                }
                                try? await Task.sleep(for: .seconds(1))
                            }
                        }
                    }

                    // Seed built-in agents on first launch.
                    let seedContext = ModelContext(Self.modelContainer)
                    AgentSeeder.seedIfNeeded(context: seedContext)

                    // Wire Mini-Chat overlay with a shared ModelContext so conversations
                    // created in Mini-Chat appear in the main app sidebar automatically.
                    let context = ModelContext(Self.modelContainer)
                    NovaOverlayViewController.shared.configure(modelContext: context)

                    // Start global hotkeys (skip in UI test environments)
                    if !CommandLine.arguments.contains("--mock-runtime") {
                        MiniChatHotkeyManager.shared.start()
                    }
                }
        }
        .modelContainer(Self.modelContainer)
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
        #endif
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Chat") { appState.route = .newChat }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Check for Updates…") {
                    updaterController.checkForUpdates(nil)
                }
                Divider()
                Button("Send Feedback…") {
                    AppState.current?.showFeedbackRequest = true
                }
                .keyboardShortcut("/", modifiers: [.command, .shift])
            }
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
