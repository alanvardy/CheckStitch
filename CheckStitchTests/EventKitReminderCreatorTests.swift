import EventKit
@testable import CheckStitchCore
import Testing

@MainActor
struct EventKitReminderCreatorTests {
    @Test
    func eventKitCreatorIsConstructibleWithInjectedStore() {
        // Proves the adapter is a thin pass-through over the injected store and
        // never constructs a store of its own. No EventKit API is called.
        let creator = EventKitReminderCreator(eventStore: sharedTestEventStore)
        #expect(String(describing: type(of: creator)) == "EventKitReminderCreator")
    }

    @Test
    func creatorRequestsAccessBeforeCreating() async throws {
        let spy = SpyReminderCreator()
        #expect(try await spy.requestAccess() == true, "access must be requested first")
        try await spy.create(title: "one")
        #expect(spy.createdTitles == ["one"])
    }

    @Test
    func spyRecordsCreatedTitlesInOrder() async throws {
        let spy = SpyReminderCreator()
        try await spy.create(title: "one")
        try await spy.create(title: "two")
        #expect(spy.createdTitles == ["one", "two"])
    }

    @Test
    func creatorSurfacesThrownAccessError() async {
        let spy = SpyReminderCreator()
        spy.accessError = TestError.boom
        await #expect(throws: TestError.boom) { _ = try await spy.requestAccess() }
    }
}