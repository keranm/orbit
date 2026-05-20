import SwiftData
import Foundation

/// A single message within a Chat.
@Model
final class Message {
    @Attribute(.unique) var id: UUID
    /// "user" or "assistant"
    var role: String
    var content: String
    var createdAt: Date
    /// True while the assistant response is still streaming.
    var isStreaming: Bool
    /// True if streaming was interrupted before completion.
    var isInterrupted: Bool

    var chat: Chat?

    init(role: String, content: String = "") {
        id = UUID()
        self.role = role
        self.content = content
        createdAt = .now
        isStreaming = false
        isInterrupted = false
    }
}
