import EventKit

/// Seam over the EventKit surface the checklist flow needs: permission and
/// per-item reminder creation. Injected via `AppEnvironment` so tests can drive
/// denial and failure without touching EventKit.
public protocol ReminderCreating: Sendable {
    func requestAccess() async throws -> Bool
    func create(title: String) async throws
}

/// Real adapter over one long-lived `EKEventStore`.
///
/// `EKReminder` holds a weak reference to its store, so a single store must
/// outlive every reminder it creates — never construct a store per call.
///
/// `@MainActor` is what makes this class implicitly `Sendable`; a non-isolated
/// class storing a non-`Sendable` `EKEventStore` cannot satisfy
/// `ReminderCreating: Sendable`.
@MainActor
public final class EventKitReminderCreator: ReminderCreating {
    public init(eventStore: EKEventStore) {
        self.eventStore = eventStore
    }

    public func requestAccess() async throws -> Bool {
        try await eventStore.requestFullAccessToReminders()
    }

    public func create(title: String) async throws {
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        try eventStore.save(reminder, commit: true)
    }

    private let eventStore: EKEventStore
}
