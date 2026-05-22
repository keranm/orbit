import SwiftData
import Foundation

@Model
final class AgentRun {
    @Attribute(.unique) var id: UUID
    var agentID: UUID
    var startedAt: Date
    var completedAt: Date?
    var statusRaw: String
    var outputText: String?
    var stepLogsData: Data?

    var agent: Agent?

    init(agentID: UUID) {
        id = UUID()
        self.agentID = agentID
        self.startedAt = .now
        self.statusRaw = "running"
    }

    var status: RunStatus {
        get { RunStatus(rawValue: statusRaw) ?? .running }
        set { statusRaw = newValue.rawValue }
    }

    var stepLogs: [StepLog] {
        guard let data = stepLogsData else { return [] }
        return (try? JSONDecoder().decode([StepLog].self, from: data)) ?? []
    }

    func saveStepLogs(_ logs: [StepLog]) {
        stepLogsData = try? JSONEncoder().encode(logs)
    }

    var durationSeconds: Double? {
        guard let completed = completedAt else { return nil }
        return completed.timeIntervalSince(startedAt)
    }
}

enum RunStatus: String, Codable {
    case running, success, failed
}
