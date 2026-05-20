import SwiftData
import Foundation

@Model
final class PromptVariable {
    @Attribute(.unique) var id: UUID
    var name: String
    var defaultValue: String

    var template: PromptTemplate?

    init(name: String, defaultValue: String = "") {
        id = UUID()
        self.name = name
        self.defaultValue = defaultValue
    }
}
