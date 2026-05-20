import SwiftUI

@Observable
@MainActor
final class AppState {
    var route: AppRoute = .newChat

    /// Pro mode toggle — persisted across launches.
    /// Uses UserDefaults directly to avoid @AppStorage / @Observable macro conflicts.
    var isProMode: Bool {
        get { UserDefaults.standard.bool(forKey: "orbitProMode") }
        set { UserDefaults.standard.set(newValue, forKey: "orbitProMode") }
    }

    func toggleProMode() {
        isProMode.toggle()
        // If toggling off while on a Pro screen, reset to the default V1 route.
        if !isProMode, case .proScreen = route {
            route = .newChat
        }
    }

    /// Nova companion state — updated by features in response to activity and runtime state.
    var novaState: NovaState = .idle

    /// Owned runtime manager. Drives runtimeStatus and Nova state.
    let runtimeManager = RuntimeManager()

    /// Current runtime status, derived from runtimeManager.
    var runtimeStatus: RuntimeStatus { runtimeManager.status }

    /// The model ref to use for new chat requests.
    var activeModelRef: String? { runtimeManager.activeModelRef }

    /// Set to true to navigate back to onboarding from anywhere in the app.
    /// MainWindowView observes this and flips its showOnboarding state.
    var showOnboardingRequest = false

    /// Shared reference for components that need the active model ref but
    /// can't hold an injected AppState (e.g. NovaOverlayViewController).
    static weak var current: AppState?

    // hasCompletedOnboarding is persisted via @AppStorage in MainWindowView — not stored here.
}

// MARK: - RuntimeStatus

enum RuntimeStatus: Equatable {
    case notInstalled
    case noModelConfigured
    case starting
    case ready
    case stopping
    case offline
    case error(String)

    var diagnosticsLabel: String {
        switch self {
        case .notInstalled:      return "not installed"
        case .noModelConfigured: return "no model configured"
        case .starting:          return "starting…"
        case .ready:             return "ready"
        case .stopping:          return "stopping…"
        case .offline:           return "offline (process not running)"
        case .error(let msg):    return "error — \(msg)"
        }
    }
}

