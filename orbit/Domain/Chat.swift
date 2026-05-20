import SwiftData
import Foundation

/// A persisted conversation session.
@Model
final class Chat {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Mesh-LLM model ref used for this conversation, e.g. the name from installed models.
    var modelRef: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Message.chat)
    var messages: [Message] = []

    init(modelRef: String) {
        id = UUID()
        title = "New Chat"
        self.modelRef = modelRef
        createdAt = .now
        updatedAt = .now
    }

    var lastMessage: Message? {
        messages.max(by: { $0.createdAt < $1.createdAt })
    }
}
