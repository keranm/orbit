import EventKit
import Foundation

/// Reads calendar events via EventKit.
struct CalendarDataSource {

    static func fetch(_ config: CalendarStepConfig) async throws -> String {
        let store = EKEventStore()
        try await requestAccess(store: store)

        let (start, end) = dateRange(for: config)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .sorted { $0.startDate < $1.startDate }

        if events.isEmpty {
            return "No calendar events found for the selected time range."
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        return events.map { event in
            var lines = ["Title: \(event.title ?? "Untitled")"]
            lines.append("When: \(formatter.string(from: event.startDate))")
            if let end = event.endDate, end != event.startDate {
                lines.append("Until: \(formatter.string(from: end))")
            }
            if let location = event.location, !location.isEmpty {
                lines.append("Location: \(location)")
            }
            if let attendees = event.attendees, !attendees.isEmpty {
                let names = attendees.compactMap { $0.name }.joined(separator: ", ")
                lines.append("Attendees: \(names)")
            }
            if let notes = event.notes, !notes.isEmpty {
                let preview = String(notes.prefix(200))
                lines.append("Notes: \(preview)")
            }
            return lines.joined(separator: "\n")
        }.joined(separator: "\n---\n")
    }

    // MARK: - Helpers

    private static func requestAccess(store: EKEventStore) async throws {
        if #available(macOS 14.0, *) {
            try await store.requestFullAccessToEvents()
        } else {
            let granted = await withCheckedContinuation { continuation in
                store.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
            guard granted else { throw DataSourceError.permissionDenied("Calendar") }
        }
    }

    private static func dateRange(for config: CalendarStepConfig) -> (Date, Date) {
        let now = Date()
        let cal = Calendar.current
        switch config.rangeType {
        case .today:
            let start = cal.startOfDay(for: now)
            let end = cal.date(byAdding: .day, value: 1, to: start)!
            return (start, end)
        case .thisWeek:
            let start = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now))!
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start)!
            return (start, end)
        case .nextNDays:
            let end = cal.date(byAdding: .day, value: config.rangeDays, to: now)!
            return (now, end)
        case .lastNDays:
            let start = cal.date(byAdding: .day, value: -config.rangeDays, to: now)!
            return (start, now)
        }
    }
}
