@testable import CheckStitch
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct RunChecklistIntentTests {
    /// A "Groceries" checklist in an isolated store, a spy wired to resolve the
    /// checklist's destination to list-1, and the intent ready to perform.
    private func makeIntent() -> (intent: RunChecklistIntent, spy: SpyReminderDestination, store: ChecklistStore) {
        let store = ChecklistStore(defaults: makeIsolatedDefaults())
        store.create(name: "Groceries")
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-1", title: "Reminders")],
            defaultIdentifier: "list-1")
        let intent = RunChecklistIntent(
            store: store,
            targeting: spy,
            gate: RunGate(counter: RunCounter(defaults: makeIsolatedDefaults()), isUnlocked: true))
        intent.checklist = ChecklistEntity(id: store.checklists[0].id.uuidString, name: "Groceries")
        return (intent: intent, spy: spy, store: store)
    }

    @Test
    func runCreatesEveryNonBlankItemAndReportsCount() async throws {
        let (intent, spy, store) = makeIntent()
        let checklistID = store.checklists[0].id
        store.addItem(to: checklistID, title: "Milk")
        store.addItem(to: checklistID, title: "   ")          // blank title → skipped
        store.addItem(to: checklistID, title: "Eggs")
        let milk = try #require(store.checklist(id: checklistID)?.items[0])
        store.updateItemDescription(checklistID: checklistID, itemID: milk.id, description: "2 litres")

        _ = try await intent.perform()

        #expect(spy.createdTitles == ["Milk", "Eggs"])
        #expect(spy.createdNotes == ["2 litres", nil])
        #expect(spy.createdListIDs == ["list-1", "list-1"])
        #expect(RunChecklistDialogue.message(for: .created(count: 2), checklistName: "Groceries")
            .resolved() == "Created 2 reminders for Groceries.")
    }

    @Test
    func runReportsExactCreatedDialogue() {
        #expect(RunChecklistDialogue.message(for: .created(count: 2), checklistName: "Groceries")
            .resolved() == "Created 2 reminders for Groceries.")
    }

    @Test
    func runReportsSingularDialogueForOneReminder() {
        #expect(RunChecklistDialogue.message(for: .created(count: 1), checklistName: "Groceries")
            .resolved() == "Created 1 reminder for Groceries.")
    }

    @Test
    func staleChecklistIdThrowsWithItsMessage() async throws {
        let (intent, spy, _) = makeIntent()
        intent.checklist = ChecklistEntity(id: UUID().uuidString, name: "Ghost")

        do {
            _ = try await intent.perform()
            Issue.record("a stale checklist id should throw, not perform")
        } catch let error as RunChecklistIntentError {
            #expect(error.errorDescription == "That checklist no longer exists.")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func notDeterminedAccessReportsInstructionAndCreatesNothing() async throws {
        let (intent, spy, _) = makeIntent()
        spy.accessStatusValue = .notDetermined

        _ = try await intent.perform()

        #expect(RunChecklistDialogue.notDetermined.resolved()
            == "Open CheckStitch and allow Reminders access, then ask again.")
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func deniedAccessReportsSettingsInstructionAndCreatesNothing() async throws {
        let (intent, spy, _) = makeIntent()
        spy.accessStatusValue = .denied

        _ = try await intent.perform()

        #expect(RunChecklistDialogue.denied.resolved()
            == "CheckStitch doesn't have permission to access Reminders. Turn it on in Settings, then ask again.")
        #expect(spy.createdTitles.isEmpty)
    }

    @Test
    func destinationMissingReportsItsDialogueAndCreatesNothing() async throws {
        let (intent, spy, _) = makeIntent()
        spy.lists = ReminderListsSnapshot(options: [], defaultIdentifier: nil)

        _ = try await intent.perform()

        #expect(RunChecklistDialogue.message(for: .destinationMissing, checklistName: "Groceries")
            .resolved() == "That list no longer exists, so no reminders were created for Groceries.")
        #expect(spy.createdTitles.isEmpty)
    }

    /// A mid-loop failure must speak the exact split (N of M created), not a
    /// generic failure — the committed items are real reminders.
    @Test
    func partialCreationReportsExactSplitDialogue() async throws {
        let (intent, spy, store) = makeIntent()
        let checklistID = store.checklists[0].id
        for title in ["Milk", "Eggs", "Bread", "Butter", "Cheese", "Yogurt", "Juice"] {
            store.addItem(to: checklistID, title: title)
        }
        spy.createFailureCount = 3

        _ = try await intent.perform()

        #expect(spy.createdTitles.count == 3)
        #expect(spy.createdTitles == ["Milk", "Eggs", "Bread"])
        #expect(RunChecklistDialogue.message(
            for: .partiallyCreated(created: 3, total: 7, reason: TestError.boom.localizedDescription),
            checklistName: "Groceries").resolved()
            == "Created 3 of 7 reminders for Groceries; the rest were not created. "
                + TestError.boom.localizedDescription)
    }

    /// `perform()` reads the store at call time, so a mutation between two asks
    /// is visible to the second ask (no cached snapshot).
    @Test
    func coldRunReadsFreshStoreEachPerform() async throws {
        let (intent, spy, store) = makeIntent()
        let checklistID = store.checklists[0].id

        _ = try await intent.perform()
        #expect(spy.createdTitles.isEmpty)

        store.addItem(to: checklistID, title: "Milk")
        _ = try await intent.perform()

        #expect(spy.createdTitles == ["Milk"])
    }

    /// The status-only pre-check runs on every `perform()`, so a grant made
    /// between two asks is honoured by the next ask.
    @Test
    func accessGrantedBetweenAsksIsHonoured() async throws {
        let (intent, spy, store) = makeIntent()
        store.addItem(to: store.checklists[0].id, title: "Milk")

        spy.accessStatusValue = .denied
        _ = try await intent.perform()
        #expect(spy.createdTitles.isEmpty)

        spy.accessStatusValue = .fullAccess
        _ = try await intent.perform()

        #expect(spy.createdTitles == ["Milk"])
    }

    /// Each state owns its exact dialogue constant, even after the status
    /// flips between asks.
    @Test
    func notDeterminedAfterPriorDenialIsStable() async throws {
        let (intent, spy, _) = makeIntent()

        spy.accessStatusValue = .denied
        _ = try await intent.perform()
        #expect(RunChecklistDialogue.denied.resolved()
            == "CheckStitch doesn't have permission to access Reminders. Turn it on in Settings, then ask again.")
        #expect(spy.createdTitles.isEmpty)

        spy.accessStatusValue = .notDetermined
        _ = try await intent.perform()
        #expect(RunChecklistDialogue.notDetermined.resolved()
            == "Open CheckStitch and allow Reminders access, then ask again.")
        #expect(spy.createdTitles.isEmpty)

        spy.accessStatusValue = .denied
        _ = try await intent.perform()
        #expect(RunChecklistDialogue.denied.resolved()
            == "CheckStitch doesn't have permission to access Reminders. Turn it on in Settings, then ask again.")
        #expect(spy.createdTitles.isEmpty)
    }

    /// A very long name must survive the dialogue helper whole — no truncation
    /// assumptions in the resolver.
    @Test
    func longChecklistNameDialogueIsWhole() {
        let longName = String(repeating: "A", count: 120)

        let dialogue = RunChecklistDialogue.message(for: .created(count: 2), checklistName: longName).resolved()

        #expect(dialogue == "Created 2 reminders for " + longName + ".")
    }

    @Test
    func purchaseRequiredSpeaksTheLimitDialogue() {
        #expect(RunChecklistDialogue.message(for: .purchaseRequired, checklistName: "Groceries")
            .resolved()
            == "You've reached the CheckStitch free limit. Open CheckStitch to buy a license.")
    }
}
