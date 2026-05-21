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

    /// Completion tokens from the stream's final usage chunk.
    var tokenCount: Int?
    /// Prompt tokens from the stream's final usage chunk.
    var promptTokenCount: Int?
    /// Wall-clock time in seconds from send() to first content token.
    var inferenceLatency: TimeInterval?
    /// True when inference ran on the local port (9337) vs. a mesh-routed node.
    var wasLocalInference: Bool = true

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
