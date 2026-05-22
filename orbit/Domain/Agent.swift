import SwiftData
import Foundation

@Model
final class Agent {
    @Attribute(.unique) var id: UUID
    var name: String
    var agentDescription: String
    var icon: String
    var isActive: Bool
    var isTemplate: Bool
    var scheduleData: Data?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \AgentStep.agent)
    var steps: [AgentStep] = []

    @Relationship(deleteRule: .cascade, inverse: \AgentRun.agent)
    var runs: [AgentRun] = []

    init(name: String, description: String = "", icon: String = "sparkles", isTemplate: Bool = false) {
        id = UUID()
        self.name = name
        self.agentDescription = description
        self.icon = icon
        self.isActive = true
        self.isTemplate = isTemplate
        self.createdAt = .now
        self.updatedAt = .now
    }

    var sortedSteps: [AgentStep] {
        steps.sorted { $0.order < $1.order }
    }

    var lastRun: AgentRun? {
        runs.max(by: { $0.startedAt < $1.startedAt })
    }
}
