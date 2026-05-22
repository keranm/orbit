import SwiftUI

@Observable
@MainActor
final class AppState {
    var route: AppRoute = .newChat

    /// Pro mode toggle — persisted across launches.
    /// Stored property so @Observable tracks access and mutation.
    /// didSet persists to UserDefaults on write.
    var isProMode: Bool = UserDefaults.standard.bool(forKey: "orbitProMode") {
        didSet { UserDefaults.standard.set(isProMode, forKey: "orbitProMode") }
    }

    func toggleProMode() {
        isProMode.toggle()
        // If toggling off while on a Pro-only route, reset to the default V1 route.
        if !isProMode {
            switch route {
            case .dashboard, .coding, .playground:
                route = .newChat
            default:
                break
            }
        }
    }

    /// Nova companion state — updated by features in response to activity and runtime state.
    var novaState: NovaState = .idle

    /// Owned runtime manager. Drives runtimeStatus and Nova state.
    let runtimeManager: RuntimeManager

    /// Mobile Access coordinator — owns all mobile services lifecycle.
    let mobileAccessCoordinator: MobileAccessCoordinator

    /// Current runtime status, derived from runtimeManager.
    var runtimeStatus: RuntimeStatus { runtimeManager.status }

    /// The model ref to use for new chat requests.
    var activeModelRef: String? { runtimeManager.activeModelRef }

    /// Set to true to navigate back to onboarding from anywhere in the app.
    /// MainWindowView observes this and flips its showOnboarding state.
    var showOnboardingRequest = false

    /// Persisted CodeViewModel so context survives navigation switches.
    var codeViewModel = CodeViewModel()

    /// When non-nil, the next view to mount should inject this prompt as chat text (NewChatView).
    var pendingChatPrompt: String?

    /// When non-nil, the next Code screen mount should use this as the active prompt.
    var pendingCodePrompt: PendingCodePrompt?

    /// Shared reference for components that need the active model ref but
    /// can't hold an injected AppState (e.g. NovaOverlayViewController).
    static weak var current: AppState?

    struct PendingCodePrompt {
        let id: UUID
        let name: String
        let body: String
    }

    // hasCompletedOnboarding is persisted via @AppStorage in MainWindowView — not stored here.

    init() {
        let rm = RuntimeManager()
        runtimeManager = rm
        mobileAccessCoordinator = MobileAccessCoordinator(
            runtimeManager: rm,
            chatService: ChatService(apiPort: rm.apiPort)
        )
    }
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

