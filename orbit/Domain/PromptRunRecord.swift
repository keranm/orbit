import SwiftData
import Foundation

/// Records a single execution of a prompt template for usage analytics.
@Model
final class PromptRunRecord {
    var templateID: UUID
    var runAt: Date = Date()
    var tokenCount: Int = 0
    var latency: TimeInterval = 0
    var wasSuccess: Bool = true

    init(templateID: UUID) {
        self.templateID = templateID
    }
}
