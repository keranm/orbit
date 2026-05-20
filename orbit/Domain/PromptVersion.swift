import SwiftData
import Foundation

@Model
final class PromptVersion {
    @Attribute(.unique) var id: UUID
    var versionNumber: Int
    var body: String
    var changeDescription: String
    var createdAt: Date

    var template: PromptTemplate?

    init(versionNumber: Int, body: String, changeDescription: String = "") {
        id = UUID()
        self.versionNumber = versionNumber
        self.body = body
        self.changeDescription = changeDescription
        createdAt = .now
    }
}
