import Foundation

// V1 navigation routes.
enum AppRoute: Hashable {
    case newChat
    case chat(id: UUID)
    case prompts
    case models
    case settings
}
