import Foundation

/// Navigation routes. Pro-only cases are gated by AppState.isProMode and
/// are not accessible when Pro mode is off.
enum AppRoute: Hashable {
    // V1 routes
    case newChat
    case chat(id: UUID)
    case prompts
    case models
    case settings

    // Pro routes (flat — no wrapper enum)
    case dashboard
    case coding
    case playground
}
