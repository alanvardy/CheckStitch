import EventKit
@testable import CheckStitchCore
import Testing

@MainActor
struct EventKitReminderCreatorTests {
    /// Crash-canary for the real adapter: it must be constructible around an
    /// injected `EKEventStore` without constructing one of its own. `EKReminder`
    /// holds a weak reference to its store, so a store built per call would
    /// deallocate underneath it (see `ReminderCreating.swift`). No EventKit API
    /// is called here; the request/create behavior is exercised through
    /// `SpyReminderCreator` in `ChecklistCreatorTests`.
    @Test
    func eventKitCreatorAcceptsInjectedStore() {
        _ = EventKitReminderCreator(eventStore: sharedTestEventStore)
    }

    /// Extends the crash-canary: `dueDateComponents` is readable on a reminder
    /// built from the injected store (no `save`), so the date-only field
    /// round-trips through the real EventKit type.
    @Test
    func eventKitReminderCarriesDateOnlyDueComponents() {
        let reminder = EKReminder(eventStore: sharedTestEventStore)
        reminder.dueDateComponents = DateComponents(year: 2026, month: 3, day: 10)
        #expect(reminder.dueDateComponents?.year == 2026)
        #expect(reminder.dueDateComponents?.month == 3)
        #expect(reminder.dueDateComponents?.day == 10)
        #expect(reminder.dueDateComponents?.hour == nil)
    }
}
