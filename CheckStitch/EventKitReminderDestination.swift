import CheckStitchCore
import EventKit
import Foundation

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

    func accessStatus() -> ReminderAccessStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .fullAccess
        case .notDetermined: return .notDetermined
        // .denied, .restricted, and .writeOnly all fail our read-then-create flow.
        default: return .denied
        }
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

    func create(title: String, notes: String?, priority: ChecklistItemPriority,
                in list: ReminderListOption, dueDateComponents: DateComponents?) async throws {
        // Re-resolve by identifier: a list deleted between pre-validation and
        // creation must throw rather than silently fall back to a nil calendar.
        guard let calendar = eventStore.calendars(for: .reminder)
            .first(where: { $0.calendarIdentifier == list.id })
        else { throw ReminderDestinationError.listMissing }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        if let notes { reminder.notes = notes }   // nil leaves notes unset
        reminder.calendar = calendar
        reminder.priority = priority.rawValue   // raw value = EventKit's scale
        if let dueDateComponents {
            reminder.dueDateComponents = dueDateComponents
        }
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
    var errorDescription: String? {
        LocalizedStringResource(
            "That list no longer exists, so some reminders may not have been created.",
            table: "Localizable", bundle: .main)
            .resolvedInAppLanguage()
    }
}
