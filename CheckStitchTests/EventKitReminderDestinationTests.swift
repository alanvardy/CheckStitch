import EventKit
@testable import CheckStitch
import Testing

@MainActor
struct EventKitReminderDestinationTests {
    /// Crash-canary for the real adapter: it must be constructible around an
    /// injected `EKEventStore` without constructing one of its own. No EventKit
    /// API is called; behavior is exercised through `SpyReminderDestination`.
    @Test
    func destinationAcceptsInjectedStore() {
        _ = EventKitReminderDestination(eventStore: sharedTestEventStore)
    }
}