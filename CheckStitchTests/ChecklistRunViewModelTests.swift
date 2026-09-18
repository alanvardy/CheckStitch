import CheckStitchCore
@testable import CheckStitch
import Foundation
import Testing

@MainActor
struct ChecklistRunViewModelTests {
    private func makeStore(items: [String]) -> (ChecklistStore, UUID) {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let id = store.create(name: "Groceries").id
        for title in items {
            store.addItem(to: id)
            let itemID = store.checklist(id: id)?.items.last?.id ?? UUID()
            store.updateItem(checklistID: id, itemID: itemID, title: title)
        }
        return (store, id)
    }

    /// A destination with a resolvable default list, so a run can succeed.
    private func resolvableDestination() -> SpyReminderDestination {
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list", title: "Reminders")],
            defaultIdentifier: "list")
        return spy
    }

    @Test
    func createdSetsThenClearsTheSuccessCheck() async {
        let (store, id) = makeStore(items: ["one"])
        let spy = resolvableDestination()
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        await viewModel.createReminders(for: id)

        #expect(spy.createdTitles == ["one"])
        #expect(viewModel.runErrorMessage == nil)
        #expect(viewModel.creating.isEmpty)
        #expect(viewModel.created.isEmpty, "the success check is cleared after its flash window")
    }

    @Test(arguments: [
        ReminderRunOutcome.destinationMissing,
        .permissionDenied,
        .partiallyCreated(created: 1, total: 2, reason: TestError.boom.localizedDescription),
        .failed(TestError.boom.localizedDescription),
    ])
    func eachFailureOutcomeSetsTheErrorMessage(_ outcome: ReminderRunOutcome) async {
        let (store, id) = makeStore(items: ["one", "two"])
        let spy = SpyReminderDestination()
        switch outcome {
        case .permissionDenied: spy.accessGranted = false
        case .destinationMissing: spy.lists = ReminderListsSnapshot(options: [], defaultIdentifier: nil)
        case .partiallyCreated:
            // A resolvable destination, or the run short-circuits to
            // `.destinationMissing` before any `create` is attempted.
            spy.lists = ReminderListsSnapshot(
                options: [ReminderListOption(id: "list", title: "Reminders")],
                defaultIdentifier: "list")
            spy.createFailureCount = 1
        case .failed:
            spy.lists = ReminderListsSnapshot(
                options: [ReminderListOption(id: "list", title: "Reminders")],
                defaultIdentifier: "list")
            spy.createError = TestError.boom
        case .created: break
        }
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        await viewModel.createReminders(for: id)

        #expect(viewModel.runErrorMessage == outcome.errorMessage)
        #expect(viewModel.created.isEmpty)
    }

    @Test
    func duplicateTapWhileCreatingIsIgnored() async {
        let (store, id) = makeStore(items: ["one"])
        let spy = resolvableDestination()
        let gate = FetchGate()
        spy.onRequestAccess = { await gate.wait() }
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        let first = Task { await viewModel.createReminders(for: id) }
        await gate.waitUntilHit()
        #expect(viewModel.creating.contains(id))

        await viewModel.createReminders(for: id)   // guard hits, returns immediately
        await gate.open()
        await first.value

        #expect(spy.createdTitles.count == 1, "a second tap must not enqueue a second run")
    }

    @Test
    func unknownChecklistIDIsANoOp() async {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let spy = resolvableDestination()
        let viewModel = ChecklistRunViewModel(store: store, targeting: spy, spinnerDuration: .zero)

        await viewModel.createReminders(for: UUID())

        #expect(spy.createdTitles.isEmpty)
        #expect(viewModel.creating.isEmpty)
    }
}
