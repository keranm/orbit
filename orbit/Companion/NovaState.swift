import Foundation

/// Visual and behavioural states that drive NovaView animation.
/// Maps to real app conditions: runtime state, inference activity, connectivity.
enum NovaState: Hashable {
    case idle         // gentle float, soft blue glow — runtime ready, no activity
    case listening    // subtle forward focus — user is composing input
    case thinking     // tighter orbit, pulse — model is processing
    case responding   // brighter glow, active orbit — tokens streaming
    case success      // warm upward drift — operation completed
    case alert        // amber tint, focused — needs attention (e.g. low memory)
    case offline      // dimmed, slow — no runtime connectivity
    case error        // muted amber-red, paused float — runtime error
}
