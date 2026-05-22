import Foundation

enum AppRoute: Hashable {
    case newChat
    case chat(id: UUID)
    case explore
    case prompts
    case models
    case settings
}
