import EventKit
import os

enum ChecklistReminders {
    private static let logger = Logger(subsystem: "app.alanvardy.CheckStitch", category: "ChecklistReminders")

    /// Creates one reminder per non-blank item in the Reminders Inbox. Failures
    /// are logged, not thrown — the caller only needs to know when to stop its
    /// spinner.
    static func create(from checklist: Checklist) async {
        let eventStore = EKEventStore()
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            if !granted { return }
            for item in checklist.items {
                // Skip blank titles so an emptied row can't produce a meaningless reminder.
                guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                let reminder = EKReminder(eventStore: eventStore)
                reminder.title = item.title
                reminder.calendar = eventStore.defaultCalendarForNewReminders()
                try eventStore.save(reminder, commit: true)
            }
        } catch {
            logger.error("Failed to create checklist reminders: \(error.localizedDescription, privacy: .public)")
        }
    }
}