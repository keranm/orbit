import SwiftData
import Foundation

@Model
final class AgentStep {
    @Attribute(.unique) var id: UUID
    var order: Int
    var stepTypeRaw: String
    var label: String
    var configData: Data?

    var agent: Agent?

    init(order: Int, stepType: StepType, label: String? = nil) {
        id = UUID()
        self.order = order
        self.stepTypeRaw = stepType.rawValue
        self.label = label ?? stepType.label
        self.configData = nil
    }

    var stepType: StepType {
        StepType(rawValue: stepTypeRaw) ?? .think
    }
}
