import Foundation

/// Accessibility support for Nova. Provides VoiceOver labels per state
/// and helpers for callers that need to decide whether to hide or announce Nova.
enum NovaAccessibility {

    /// Human-readable VoiceOver label for each state.
    static func label(for state: NovaState) -> String {
        switch state {
        case .idle:       return "Nova — ready"
        case .listening:  return "Nova — listening"
        case .thinking:   return "Nova — thinking"
        case .responding: return "Nova — responding"
        case .success:    return "Nova — done"
        case .alert:      return "Nova — needs attention"
        case .offline:    return "Nova — offline"
        case .error:      return "Nova — error"
        }
    }

    /// Returns true for states that carry meaningful status information a VoiceOver
    /// user should hear. Decorative idle animation is silent.
    static func shouldAnnounce(_ state: NovaState) -> Bool {
        switch state {
        case .idle, .listening, .responding: return false
        case .thinking, .success, .alert, .offline, .error: return true
        }
    }
}
