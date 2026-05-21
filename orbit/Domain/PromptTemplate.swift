import SwiftData
import Foundation

@Model
final class PromptTemplate: Identifiable {
    @Attribute(.unique) var id: UUID
    var name: String
    var templateDescription: String
    var tags: [String]
    /// Template body with `{{variable}}` placeholders.
    var body: String
    var createdAt: Date
    var updatedAt: Date
    var version: Int
    /// Optional model ref to use when testing this prompt.
    var modelAssociation: String?
    var usageCount: Int
    var notes: String = ""

    @Relationship(deleteRule: .cascade, inverse: \PromptVariable.template)
    var variables: [PromptVariable] = []

    @Relationship(deleteRule: .cascade, inverse: \PromptVersion.template)
    var versions: [PromptVersion] = []

    init(
        name: String,
        description: String = "",
        tags: [String] = [],
        body: String = "",
        modelAssociation: String? = nil
    ) {
        id = UUID()
        self.name = name
        self.templateDescription = description
        self.tags = tags
        self.body = body
        self.modelAssociation = modelAssociation
        createdAt = .now
        updatedAt = .now
        version = 1
        usageCount = 0
        notes = ""
    }
}
