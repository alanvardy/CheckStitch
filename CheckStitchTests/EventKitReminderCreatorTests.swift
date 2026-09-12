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
}
