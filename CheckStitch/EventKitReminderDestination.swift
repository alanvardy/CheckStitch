import CheckStitchCore
import EventKit

/// Real adapter over one long-lived `EKEventStore`: enumerates Reminders lists
/// and creates reminders in a chosen one. `shared` is the production instance —
/// it must outlive every reminder it creates (`EKReminder` holds a weak
/// reference to its store).
@MainActor
final class EventKitReminderDestination: ReminderDestinationTargeting {
    static let shared = EventKitReminderDestination()

    init(eventStore: EKEventStore = EKEventStore()) {
        self.eventStore = eventStore
    }

    func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    func reminderLists() async throws -> ReminderListsSnapshot {
        ReminderListsSnapshot(
            options: eventStore.calendars(for: .reminder).compactMap { calendar in
                let identifier = calendar.calendarIdentifier
                guard !identifier.isEmpty else { return nil }
                return ReminderListOption(id: identifier, title: calendar.title)
            },
            defaultIdentifier: eventStore.defaultCalendarForNewReminders()?.calendarIdentifier)
    }

    func create(title: String, in list: ReminderListOption) async throws {
        // Re-resolve by identifier: a list deleted between pre-validation and
        // creation must throw rather than silently fall back to a nil calendar.
        guard let calendar = eventStore.calendars(for: .reminder)
            .first(where: { $0.calendarIdentifier == list.id })
        else { throw ReminderDestinationError.listMissing }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = calendar
        // watchOS EventKit is read-only; the watch never reaches this adapter.
        #if !os(watchOS)
            try eventStore.save(reminder, commit: true)
        #endif
    }

    private let eventStore: EKEventStore
}

enum ReminderDestinationError: LocalizedError {
    case listMissing

    /// Distinct from `ReminderRunOutcome.destinationMissing`'s message: this is
    /// thrown mid-loop (TOCTOU), so earlier items may already have been created.
    var errorDescription: String? { "That list no longer exists, so some reminders may not have been created." }
}
