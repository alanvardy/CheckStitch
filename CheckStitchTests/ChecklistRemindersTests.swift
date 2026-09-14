@testable import CheckStitch
import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistRemindersTests {
    private func snapshot(defaultIdentifier: String? = "list-default") -> ReminderListsSnapshot {
        ReminderListsSnapshot(
            options: [
                ReminderListOption(id: "list-default", title: "Reminders"),
                ReminderListOption(id: "list-a", title: "Groceries"),
            ],
            defaultIdentifier: defaultIdentifier)
    }

    @Test
    func createsInChosenList() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("Eggs")],
                                  destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["Milk", "Eggs"])
        #expect(spy.createdListIDs == ["list-a", "list-a"])
    }

    @Test
    func nilDestinationUsesDefaultList() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot(defaultIdentifier: "list-default")
        let checklist = Checklist(items: [makeItem("Milk")])

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 1))
        #expect(spy.createdListIDs == ["list-default"])
    }

    /// Sad path: a destination that no longer exists must create ZERO reminders.
    @Test
    func missingDestinationCreatesNothing() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("Eggs")],
                                  destinationListIdentifier: "list-deleted")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty)
        #expect(spy.createdListIDs.isEmpty)
    }

    /// Sad path: no default list at all is a failure, not a silent skip.
    @Test
    func missingDefaultCreatesNothing() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot(defaultIdentifier: nil)
        let checklist = Checklist(items: [makeItem("Milk")])

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func permissionDeniedReturnsDenied() async {
        let spy = SpyReminderDestination()
        spy.accessGranted = false
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .permissionDenied)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func blankTitlesAreSkipped() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("   "), makeItem("")],
                                  destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 1))
        #expect(spy.createdTitles == ["Milk"])
    }

    @Test
    func notesForwardDescription() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(
            items: [makeItem("Milk", description: "2 litres"), makeItem("Eggs", description: "a dozen")],
            destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdNotes == ["2 litres", "a dozen"])
    }

    @Test
    func blankDescriptionSendsNilNotes() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        _ = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(spy.createdNotes == [nil])
    }

    @Test
    func whitespaceOnlyDescriptionSendsNilNotes() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk", description: "   ")], destinationListIdentifier: "list-a")

        _ = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(spy.createdNotes == [nil])
    }

    /// Sad path: the existing denial/missing-destination guards still create
    /// nothing, so no notes can leak.
    @Test
    func deniedAccessNeverSendsNotes() async {
        let spy = SpyReminderDestination()
        spy.accessGranted = false
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk", description: "2 litres")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .permissionDenied)
        #expect(spy.createdNotes.isEmpty)
    }

    @Test
    func saveFailureReturnsFailed() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        spy.createError = TestError.boom
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
    }

    @Test
    func errorMessagesDescribeEachFailure() {
        #expect(ReminderRunOutcome.created(count: 1).errorMessage == nil)
        #expect(ReminderRunOutcome.destinationMissing.errorMessage == "That list no longer exists; no reminders were created.")
        #expect(ReminderRunOutcome.permissionDenied.errorMessage != nil)
        #expect(ReminderRunOutcome.failed("boom").errorMessage == "boom")
    }

    /// Parity for the live path: the run orchestrator must pass the item's
    /// date-only components to the seam. The real `Date()` today is not pinned,
    /// so only structural properties are asserted — present and time-less when
    /// the item carries a relative date, absent when it has none.
    @Test
    func relativeDatesCarryToTheSeam() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(
            items: [
                ChecklistItem(title: "Milk", relativeDate: 0),
                makeItem("Eggs"),
            ],
            destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        guard let date = spy.createdDates[0] else {
            Issue.record("expected a date on the relative-date item")
            return
        }
        #expect(date.hour == nil, "the live path passes date-only components")
        #expect(date.minute == nil)
        #expect(spy.createdDates[1] == nil)
    }
}
