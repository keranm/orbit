import AppKit
import SwiftUI
import SwiftData

/// Manages the Nova Mini-Chat overlay presentation.
///
/// The overlay uses a borderless, transparent, non-activating NSPanel so the
/// previously-active app stays visually front while Nova intercepts keyboard input.
/// No title bar, no traffic lights, no window chrome — all depth comes from SwiftUI
/// materials and shadow.
@MainActor
final class NovaOverlayViewController {

    static let shared = NovaOverlayViewController()

    // MARK: - State

    private var panel: BorderlessKeyPanel?
    private var previousApp: NSRunningApplication?
    private let viewModel = MiniChatPanelViewModel()

    // MARK: - Init

    private init() {}

    // MARK: - Public API

    var isVisible: Bool { panel?.isVisible ?? false }

    func configure(modelContext: ModelContext?) {
        viewModel.configure(
            modelRef: AppState.current?.activeModelRef,
            systemMessage: PromptSettings.buildSystemMessage(),
            modelContext: modelContext
        )
    }

    func toggle() {
        if isVisible {
            dismiss()
        } else {
            show()
        }
    }

    func show() {
        // Re-sync model ref and system prompt on every show so changes made in
        // the main app (Models screen, Prompts screen) are picked up immediately.
        viewModel.configure(
            modelRef: AppState.current?.activeModelRef,
            systemMessage: PromptSettings.buildSystemMessage(),
            modelContext: nil  // context already wired at launch; nil preserves it
        )

        // Check runtime availability before showing
        let runtimeStatus = AppState.current?.runtimeStatus
        guard runtimeStatus == .ready || runtimeStatus == nil else {
            // Runtime unavailable — route to the main app where the chat home
            // already handles each runtime state gracefully (paused, not installed, etc.)
            escalateToMainApp()
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication

        let panel = ensurePanel()
        positionPanel(panel)

        // Reset phase to appearing before making visible
        viewModel.phase = .hidden
        panel.orderFrontRegardless()
        panel.makeKey()

        // Sequence: hidden → appearing → listening
        withAnimation(.easeIn(duration: 0.01)) {
            viewModel.phase = .appearing
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [weak self] in
            guard let self, self.isVisible else { return }
            withAnimation(.spring(duration: 0.38, bounce: 0.1)) {
                self.viewModel.phase = .listening
            }
        }
    }

    func dismiss() {
        // Sequence: current → dismissing → hidden, then hide window
        withAnimation(.easeIn(duration: 0.18)) {
            viewModel.phase = .dismissing
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20) { [weak self] in
            self?.panel?.orderOut(nil)
            self?.viewModel.phase = .hidden
            // Restore focus to the previously active app
            if let prev = self?.previousApp,
               prev.bundleIdentifier != Bundle.main.bundleIdentifier {
                prev.activate(options: [])
            }
            self?.previousApp = nil
        }
    }

    // MARK: - Private — panel setup

    private func ensurePanel() -> BorderlessKeyPanel {
        if let existing = panel { return existing }

        let screen = NSScreen.main ?? NSScreen.screens[0]
        let panelWidth:  CGFloat = 600
        let panelHeight: CGFloat = 650
        let originX = screen.frame.midX - panelWidth / 2
        // Position at top of screen (AppKit Y=0 is bottom)
        let originY = screen.frame.maxY - panelHeight - (NSStatusBar.system.thickness + 4)

        let p = BorderlessKeyPanel(
            contentRect: NSRect(x: originX, y: originY, width: panelWidth, height: panelHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false   // SwiftUI materials provide their own depth
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        p.isReleasedWhenClosed = false
        p.animationBehavior = .none

        let hostingView = NSHostingView(
            rootView: MiniChatPanelView(viewModel: viewModel).ignoresSafeArea()
        )
        p.contentView = hostingView

        self.panel = p
        return p
    }

    private func positionPanel(_ panel: BorderlessKeyPanel) {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let pw = panel.frame.width
        let ph = panel.frame.height
        let x  = screen.frame.midX - pw / 2
        let y  = screen.frame.maxY - ph - (NSStatusBar.system.thickness + 4)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func escalateToMainApp() {
        NSApp.activate(ignoringOtherApps: true)
        if let state = AppState.current {
            if state.runtimeStatus == .notInstalled {
                // Truly not set up — send back through onboarding
                state.showOnboardingRequest = true
            } else {
                // Runtime exists but is paused/unavailable — chat home handles it
                state.route = .newChat
            }
        }
        NSApp.windows
            .first(where: { !($0 is NSPanel) })?
            .makeKeyAndOrderFront(nil)
    }
}

// MARK: - Borderless panel that can become key

/// NSPanel subclass that allows becoming the key window without `.titled` style mask.
/// Required so SwiftUI text fields inside a `.borderless` panel can receive focus.
final class BorderlessKeyPanel: NSPanel {
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { false }
}
