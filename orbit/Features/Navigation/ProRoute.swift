import Foundation

enum ProRoute: Hashable {
    case dashboard
    case coding
    case playground
    case prompts
    case promptEditor(id: UUID)
}
