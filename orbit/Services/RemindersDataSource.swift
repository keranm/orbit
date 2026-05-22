import EventKit
import Foundation

/// Reads reminders via EventKit.
struct RemindersDataSource {

    static func fetch(_ config: RemindersStepConfig) async throws -> String {
        let store = EKEventStore()
        try await requestAccess(store: store)

        let calendars: [EKCalendar]
        if config.listName.isEmpty {
            calendars = store.calendars(for: .reminder)
        } else {
            calendars = store.calendars(for: .reminder).filter {
                $0.title.localizedCaseInsensitiveContains(config.listName)
            }
        }

        guard !calendars.isEmpty else {
            return "No reminder lists found\(config.listName.isEmpty ? "" : " matching '\(config.listName)'")"
        }

        let predicate = config.incompleteOnly
            ? store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendars)
            : store.predicateForReminders(in: calendars)

        let reminders = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) { result in
                cont.resume(returning: result ?? [])
            }
        }

        if reminders.isEmpty {
            return "No reminders found."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return reminders.map { reminder in
            var parts = ["• \(reminder.title ?? "Untitled")"]
            if let due = reminder.dueDateComponents?.date {
                parts.append("Due: \(formatter.string(from: due))")
            }
            if let notes = reminder.notes, !notes.isEmpty {
                parts.append("Notes: \(String(notes.prefix(100)))")
            }
            return parts.joined(separator: " | ")
        }.joined(separator: "\n")
    }

    private static func requestAccess(store: EKEventStore) async throws {
        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToReminders()
        } else {
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { throw DataSourceError.permissionDenied("Reminders") }
        }
    }
}
