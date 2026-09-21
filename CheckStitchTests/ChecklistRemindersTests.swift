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

    /// Gate-free seam for the existing sequencing/outcome tests: unlocked, and its
    /// counter lives in an isolated suite.
    private func create(_ checklist: Checklist,
                        targeting: SpyReminderDestination) async -> ReminderRunOutcome {
        let gate = RunGate(counter: RunCounter(defaults: makeIsolatedDefaults()),
                           isUnlocked: true)
        return await ChecklistReminders.create(from: checklist, targeting: targeting, gate: gate)
    }

    @Test
    func createsInChosenList() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("Eggs")],
                                  destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["Milk", "Eggs"])
        #expect(spy.createdListIDs == ["list-a", "list-a"])
    }

    @Test
    func nilDestinationUsesDefaultList() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot(defaultIdentifier: "list-default")
        let checklist = Checklist(items: [makeItem("Milk")])

        let outcome = await create(checklist, targeting: spy)

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

        let outcome = await create(checklist, targeting: spy)

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

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func permissionDeniedReturnsDenied() async {
        let spy = SpyReminderDestination()
        spy.accessGranted = false
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .permissionDenied)
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func blankTitlesAreSkipped() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("   "), makeItem("")],
                                  destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

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

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdNotes == ["2 litres", "a dozen"])
    }

    @Test
    func blankDescriptionSendsNilNotes() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        _ = await create(checklist, targeting: spy)

        #expect(spy.createdNotes == [nil])
    }

    @Test
    func whitespaceOnlyDescriptionSendsNilNotes() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk", description: "   ")], destinationListIdentifier: "list-a")

        _ = await create(checklist, targeting: spy)

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

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .permissionDenied)
        #expect(spy.createdNotes.isEmpty)
    }

    @Test
    func saveFailureReturnsFailed() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        spy.createError = TestError.boom
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
    }

    /// Mid-loop throw after some creates: the committed items are reported as an
    /// exact split, never as a generic failure.
    @Test
    func midLoopThrowAfterSomeCreatesReportsPartiallyCreated() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        spy.createFailureCount = 3
        let checklist = Checklist(items: [
            makeItem("Milk"), makeItem("Eggs"), makeItem("Bread"),
            makeItem("Butter"), makeItem("Cheese"), makeItem("Yogurt"), makeItem("Juice"),
        ], destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .partiallyCreated(
            created: 3, total: 7, reason: TestError.boom.localizedDescription))
        #expect(spy.createdTitles.count == 3)
    }

    /// `total` counts only non-blank items, matching the loop predicate — a
    /// blank item never inflates the denominator of a partial report.
    @Test
    func midLoopThrowTotalExcludesBlankItems() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        spy.createFailureCount = 2
        let checklist = Checklist(items: [
            makeItem("Milk"), makeItem("   "), makeItem("Eggs"), makeItem("Bread"),
        ], destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .partiallyCreated(
            created: 2, total: 3, reason: TestError.boom.localizedDescription))
    }

    /// Throw on the very first create: zero items were committed, so the run is
    /// still a plain `.failed` — `.partiallyCreated` is only for real splits.
    @Test
    func midLoopThrowBeforeAnyCreateStillReportsFailed() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        spy.createFailureCount = 0
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("Eggs")], destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .failed(TestError.boom.localizedDescription))
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func errorMessagesDescribeEachFailure() {
        #expect(ReminderRunOutcome.created(count: 1).errorMessage == nil)
        #expect(ReminderRunOutcome.destinationMissing.errorMessage == "That list no longer exists; no reminders were created.")
        #expect(ReminderRunOutcome.permissionDenied.errorMessage != nil)
        #expect(ReminderRunOutcome.purchaseRequired.errorMessage != nil)
        #expect(ReminderRunOutcome.failed("boom").errorMessage == "boom")
    }

    /// The enum's raw value is `EKReminder.priority`'s scale (none→0, low→9,
    /// medium→5, high→1), so the run path forwards the pick unchanged and the
    /// adapter writes the raw value straight through.
    @Test(arguments: ChecklistItemPriority.allCases)
    func prioritiesCarryToTheSeam(_ priority: ChecklistItemPriority) async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(
            items: [ChecklistItem(title: "Milk", priority: priority)],
            destinationListIdentifier: "list-a")

        _ = await create(checklist, targeting: spy)

        #expect(spy.createdPriorities == [priority])
        var expectedRawValue = 0
        switch priority {
        case .none: expectedRawValue = 0
        case .low: expectedRawValue = 9
        case .medium: expectedRawValue = 5
        case .high: expectedRawValue = 1
        }
        #expect(priority.rawValue == expectedRawValue)
    }

    /// Items without a pick default to `.none` (raw value 0) at the seam.
    @Test
    func defaultItemsSendNonePriority() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        _ = await create(checklist, targeting: spy)

        #expect(spy.createdPriorities == [.none])
        #expect(ChecklistItemPriority.none.rawValue == 0)
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

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdPriorities == [.none, .none], "every create carries a priority, index-aligned with createdTitles")
        guard let date = spy.createdDates[0] else {
            Issue.record("expected a date on the relative-date item")
            return
        }
        #expect(date.hour == nil, "the live path passes date-only components")
        #expect(date.minute == nil)
        #expect(spy.createdDates[1] == nil)
    }

    @Test
    func numberingIsOffByDefault() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("one"), makeItem("two")],
                                  destinationListIdentifier: "list-a")

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["one", "two"])
    }

    @Test
    func numberingPrefixesTitlesWithTheirPosition() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("one"), makeItem("two")],
                                  destinationListIdentifier: "list-a",
                                  prefixesReminderNumbers: true)

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["1: one", "2: two"])
    }

    @Test
    func numberingSkipsBlankItemsWithoutGaps() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(
            items: [makeItem("one"), makeItem(""), makeItem("two"), makeItem("   ")],
            destinationListIdentifier: "list-a",
            prefixesReminderNumbers: true)

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 2))
        #expect(spy.createdTitles == ["1: one", "2: two"])
    }

    @Test
    func numberingContinuesPastNine() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(
            items: (1...10).map { makeItem("item \($0)") },
            destinationListIdentifier: "list-a",
            prefixesReminderNumbers: true)

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 10))
        #expect(spy.createdTitles.first == "01: item 1")
        #expect(spy.createdTitles[4] == "05: item 5")
        #expect(spy.createdTitles.last == "10: item 10")
    }

    @Test
    func numberingStaysUnpaddedUpToNine() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(
            items: (1...9).map { makeItem("item \($0)") },
            destinationListIdentifier: "list-a",
            prefixesReminderNumbers: true)

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .created(count: 9))
        #expect(spy.createdTitles.first == "1: item 1")
        #expect(spy.createdTitles.last == "9: item 9")
    }

    /// Sad path: an unresolvable destination must create ZERO reminders even
    /// with numbering on — validation happens before the first title is formed.
    @Test
    func numberingStillReportsMissingDestination() async {
        let spy = SpyReminderDestination()
        spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("one")],
                                  destinationListIdentifier: "list-deleted",
                                  prefixesReminderNumbers: true)

        let outcome = await create(checklist, targeting: spy)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty)
    }

    /// The 20th run is the last free run; a successful 20th increments to the limit.
    @Test
    func twentiethRunIsAllowedAndCounted() async {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        for _ in 0..<19 { counter.increment() }
        let gate = RunGate(counter: counter, isUnlocked: false)
        let spy = SpyReminderDestination(); spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

        #expect(outcome == .created(count: 1))
        #expect(counter.count == 20)
    }

    @Test
    func twentyFirstRunIsRefusedBeforeAnyEventKitWork() async {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        for _ in 0..<20 { counter.increment() }
        let gate = RunGate(counter: counter, isUnlocked: false)
        let spy = SpyReminderDestination(); spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

        #expect(outcome == .purchaseRequired)
        #expect(spy.createdTitles.isEmpty)
        #expect(spy.requestAccessCount == 0, "the gate is checked before any EventKit call")
        #expect(counter.count == 20, "a refused run does not advance the counter")
    }

    @Test
    func failedRunDoesNotAdvanceTheCounter() async {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        let gate = RunGate(counter: counter, isUnlocked: false)
        let spy = SpyReminderDestination(); spy.lists = snapshot()
        spy.createError = TestError.boom
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

        guard case .failed = outcome else {
            Issue.record("expected .failed, got \(outcome)")
            return
        }
        #expect(counter.count == 0, "a failed run does not advance the counter")
    }

    @Test
    func partialRunDoesNotAdvanceTheCounter() async {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        let gate = RunGate(counter: counter, isUnlocked: false)
        let spy = SpyReminderDestination(); spy.lists = snapshot()
        spy.createFailureCount = 1
        let checklist = Checklist(items: [makeItem("Milk"), makeItem("Eggs")],
                                  destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

        #expect(outcome == .partiallyCreated(
            created: 1, total: 2, reason: TestError.boom.localizedDescription))
        #expect(counter.count == 0, "a partial run does not advance the counter")
    }

    @Test
    func unlockedUserRunsPastTheLimit() async {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        for _ in 0..<20 { counter.increment() }
        let gate = RunGate(counter: counter, isUnlocked: true)
        let spy = SpyReminderDestination(); spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("Milk")], destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

        #expect(outcome == .created(count: 1))
        #expect(counter.count == RunGate.freeRunLimit, "an unlocked counter is capped, not unbounded")
    }

    /// An all-blank run creates nothing and must not consume a free slot.
    @Test
    func emptyRunDoesNotAdvanceTheCounter() async {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        for _ in 0..<19 { counter.increment() }
        let gate = RunGate(counter: counter, isUnlocked: false)
        let spy = SpyReminderDestination(); spy.lists = snapshot()
        let checklist = Checklist(items: [makeItem("   "), makeItem("")],
                                  destinationListIdentifier: "list-a")

        let outcome = await ChecklistReminders.create(from: checklist, targeting: spy, gate: gate)

        #expect(outcome == .created(count: 0))
        #expect(counter.count == 19, "a run that created nothing does not consume a free run")
    }

    /// Reservation is atomic: two gates sharing a counter at `limit - 1` cannot
    /// both claim the last slot.
    @Test
    func concurrentReservationsCannotBothPassTheLimit() async {
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        for _ in 0..<19 { counter.increment() }
        var first = RunGate(counter: counter, isUnlocked: false)
        var second = RunGate(counter: counter, isUnlocked: false)

        let firstReserved = first.reserveRun()
        let secondReserved = second.reserveRun()
        #expect(firstReserved)
        #expect(!secondReserved, "the second reservation sees the first's increment")
        #expect(counter.count == 20)
    }
}
