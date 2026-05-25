import Foundation
import CoreTransferable

// MARK: - Step types

enum StepType: String, CaseIterable, Codable {
    case readMail
    case readCalendar
    case readReminders
    case readFiles
    case readRSS
    case think
    case condition
    case output

    var label: String {
        switch self {
        case .readMail:      return "Read Mail"
        case .readCalendar:  return "Read Calendar"
        case .readReminders: return "Read Reminders"
        case .readFiles:     return "Read Files"
        case .readRSS:       return "Read RSS"
        case .think:         return "Think"
        case .condition:     return "Condition"
        case .output:        return "Output"
        }
    }

    var subtitle: String {
        switch self {
        case .readMail:      return "Email, files"
        case .readCalendar:  return "Events, meetings"
        case .readReminders: return "To-dos, lists"
        case .readFiles:     return "Docs, folders"
        case .readRSS:       return "News, feeds"
        case .think:         return "Use the model"
        case .condition:     return "IF / THEN"
        case .output:        return "Show result"
        }
    }

    var icon: String {
        switch self {
        case .readMail:      return "envelope"
        case .readCalendar:  return "calendar"
        case .readReminders: return "checkmark.circle"
        case .readFiles:     return "folder"
        case .readRSS:       return "dot.radiowaves.left.and.right"
        case .think:         return "brain"
        case .condition:     return "arrow.triangle.branch"
        case .output:        return "square.and.arrow.up"
        }
    }
}

// MARK: - Step config structs (all Codable, JSON-encoded into AgentStep.configData)

struct MailStepConfig: Codable {
    var fromFilter: String = ""
    var subjectFilter: String = ""
    var dateRangeHours: Int = 24
    var maxItems: Int = 25
    var unreadOnly: Bool = true
}

struct CalendarStepConfig: Codable {
    enum RangeType: String, Codable {
        case today, thisWeek, nextNDays, lastNDays
    }
    var rangeType: RangeType = .today
    var rangeDays: Int = 7
    var calendarNames: [String] = []
}

struct RemindersStepConfig: Codable {
    var listName: String = ""
    var incompleteOnly: Bool = true
}

struct FilesStepConfig: Codable {
    var folderPath: String = ""
    var recursive: Bool = false
    var fileTypes: [String] = []
    var maxFiles: Int = 20
}

struct RSSStepConfig: Codable {
    var feedURLs: [String] = []
    var maxItemsPerFeed: Int = 10
    var includeContent: Bool = false
}

struct ThinkStepConfig: Codable {
    var systemPrompt: String = ""
    var userPromptTemplate: String = ""
    var modelRef: String = ""
    var temperature: Double = 0.7
    var maxTokens: Int = 1024
}

struct ConditionStepConfig: Codable {
    var evaluationPrompt: String = ""
    var inputStepOrder: Int = 0
    var skipNextIfFalse: Bool = true
}

struct OutputStepConfig: Codable {
    enum Format: String, Codable {
        case text, markdown, bullets
    }
    var format: Format = .markdown
    var copyToClipboard: Bool = false
    var createReminder: Bool = false
    var reminderTitle: String = ""
}

// MARK: - Run progress events (not persisted — used during execution)

enum AgentProgress {
    case stepStarted(Int, String)       // order, label
    case stepCompleted(Int, String)     // order, output snippet
    case stepSkipped(Int)
    case llmToken(String)
    case done(String)
    case failed(String, Int?)           // message, step order
}

// MARK: - Step log (stored as JSON in AgentRun.stepLogsData)

struct StepLog: Codable {
    var stepOrder: Int
    var stepLabel: String
    var status: String                  // "completed" | "skipped" | "failed"
    var output: String?
    var durationSeconds: Double
}

// MARK: - Schedule config

struct AgentSchedule: Codable {
    enum Frequency: String, Codable, CaseIterable {
        case manual = "Manually only"
        case daily  = "Every day"
        case weekly = "Every week"
    }

    var frequency: Frequency = .manual
    var hour: Int = 9
    var minute: Int = 0
    var weekday: Int = 2   // 2 = Monday (Calendar weekday index)
}

extension Agent {
    var schedule: AgentSchedule {
        get { (scheduleData.flatMap { try? JSONDecoder().decode(AgentSchedule.self, from: $0) }) ?? AgentSchedule() }
        set { scheduleData = try? JSONEncoder().encode(newValue) }
    }
}

// MARK: - Data source errors

enum DataSourceError: LocalizedError {
    case permissionDenied(String)
    case missingConfiguration(String)
    case scriptCompilationFailed
    case scriptExecutionFailed(String)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let source):
            return "Orbit doesn't have permission to access \(source). You can grant access in System Settings > Privacy & Security."
        case .missingConfiguration(let msg):
            return msg
        case .scriptCompilationFailed:
            return "Could not prepare the Mail reader. Make sure Mail.app is installed."
        case .scriptExecutionFailed(let msg):
            return "Mail reader error: \(msg)"
        case .fetchFailed(let msg):
            return msg
        }
    }
}

// MARK: - Drag & Drop transfer types

extension StepType: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.rawValue) { rawValue in
            StepType(rawValue: rawValue) ?? .think
        }
    }
}

struct StepIDTransfer: Transferable {
    let id: UUID
    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.id.uuidString) { uuidString in
            StepIDTransfer(id: UUID(uuidString: uuidString) ?? UUID())
        }
    }
}

// MARK: - Config encoding helpers

extension AgentStep {
    func decodedConfig<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = configData else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func encodeConfig<T: Encodable>(_ config: T) {
        configData = try? JSONEncoder().encode(config)
    }
}
