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

    /// A purchase service backed by the spy seam, so `createReminders` never
    /// touches real StoreKit. `unlocked` seeds a cached verification.
    private func makePurchases(unlocked: Bool = false) -> PurchaseService {
        let cache = PurchaseEntitlementCache(defaults: makeIsolatedDefaults())
        let provider = SpyPurchaseProvider()
        provider.entitlement = unlocked
        if unlocked { cache.setVerified(true) }
        return PurchaseService(provider: provider, cache: cache)
    }

    private func makeViewModel(store: ChecklistStore,
                               targeting: any ReminderDestinationTargeting,
                               counter: RunCounter = RunCounter(defaults: makeIsolatedDefaults()),
                               purchases: PurchaseService? = nil) -> ChecklistRunViewModel {
        ChecklistRunViewModel(store: store,
                              targeting: targeting,
                              counter: counter,
                              purchases: purchases ?? makePurchases(),
                              spinnerDuration: .zero)
    }

    @Test
    func createdSetsThenClearsTheSuccessCheck() async {
        let (store, id) = makeStore(items: ["one"])
        let spy = resolvableDestination()
        let viewModel = makeViewModel(store: store, targeting: spy)

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
        case .purchaseRequired: break  // paywall path covered by refusalAtTheLimitPresentsThePaywall
        case .destinationRequired: break  // opens the sheet, not an alert (covered by the prompt-presentation tests)
        }
        let viewModel = makeViewModel(store: store, targeting: spy)

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
        let viewModel = makeViewModel(store: store, targeting: spy)

        let first = Task { await viewModel.createReminders(for: id) }
        await gate.waitUntilHit()
        #expect(viewModel.creating.contains(id))

        await viewModel.createReminders(for: id)   // guard hits, returns immediately
        await gate.open()
        await first.value

        #expect(spy.createdTitles.count == 1, "a second tap must not enqueue a second run")
    }

    /// Like `makeStore` but every item is explicitly disabled, so nothing is runnable.
    private func makeAllDisabledStore(items: [String]) -> (ChecklistStore, UUID) {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let id = store.create(name: "Groceries").id
        for title in items {
            store.addItem(to: id)
            let itemID = store.checklist(id: id)?.items.last?.id ?? UUID()
            store.updateItem(checklistID: id, itemID: itemID, title: title)
            store.updateItem(checklistID: id, itemID: itemID, isEnabled: false)
        }
        return (store, id)
    }

    @Test
    func unknownChecklistIDIsANoOp() async {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let spy = resolvableDestination()
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.createReminders(for: UUID())

        #expect(spy.createdTitles.isEmpty)
        #expect(viewModel.creating.isEmpty)
    }

    @Test
    func refusalAtTheLimitPresentsThePaywall() async {
        let (store, id) = makeStore(items: ["one"])
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        for _ in 0..<20 { counter.increment() }
        let spy = resolvableDestination()
        let viewModel = makeViewModel(store: store, targeting: spy, counter: counter)

        await viewModel.createReminders(for: id)

        #expect(viewModel.isShowingPaywall)
        #expect(viewModel.runErrorMessage == nil)
        #expect(spy.createdTitles.isEmpty)
        viewModel.dismissPaywall()
        #expect(!viewModel.isShowingPaywall)
    }

    @Test
    func unlockedPurchaseRunsPastTheLimit() async {
        let (store, id) = makeStore(items: ["one"])
        let counter = RunCounter(defaults: makeIsolatedDefaults())
        for _ in 0..<20 { counter.increment() }
        let spy = resolvableDestination()
        let viewModel = makeViewModel(store: store, targeting: spy, counter: counter,
                                      purchases: makePurchases(unlocked: true))

        await viewModel.createReminders(for: id)

        #expect(!viewModel.isShowingPaywall)
        #expect(spy.createdTitles == ["one"])
    }

    @Test
    func createRemindersProceedsWhenAtLeastOneItemIsRunnable() async {
        // One titled (runnable) item and one blank item: only the runnable one runs.
        let (store, id) = makeStore(items: ["milk", ""])
        let spy = resolvableDestination()
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.createReminders(for: id)

        #expect(spy.createdTitles == ["milk"])
        #expect(viewModel.creating.isEmpty)
        #expect(viewModel.created.isEmpty)
    }

    @Test
    func createRemindersIsANoOpWhenEveryItemIsDisabled() async {
        let (store, id) = makeAllDisabledStore(items: ["milk", "eggs"])
        let spy = resolvableDestination()
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.createReminders(for: id)

        #expect(spy.createdTitles.isEmpty, "nothing is created for a fully disabled checklist")
        #expect(viewModel.creating.isEmpty, "the guard returns before `creating` is ever set")
        #expect(viewModel.created.isEmpty)
        #expect(viewModel.runErrorMessage == nil)
    }

    @Test
    func createRemindersIsANoOpWhenEveryItemIsBlank() async {
        let (store, id) = makeStore(items: ["", ""])
        let spy = resolvableDestination()
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.createReminders(for: id)

        #expect(spy.createdTitles.isEmpty, "blank items never produce reminders")
        #expect(viewModel.creating.isEmpty, "the guard returns before `creating` is ever set")
        #expect(viewModel.created.isEmpty)
        #expect(viewModel.runErrorMessage == nil)
    }

    /// A prompt checklist with no override offers its explicit lists and opens
    /// the sheet rather than showing an error.
    @Test
    func promptRunPresentsDestinationChooser() async {
        let (store, id) = makeStore(items: ["one"])
        store.setDestination(.prompt, for: id)
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [
                ReminderListOption(id: "list-inbox", title: "Inbox"),
                ReminderListOption(id: "list-groceries", title: "Groceries"),
            ],
            defaultIdentifier: "list-inbox")
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.createReminders(for: id)

        #expect(viewModel.destinationPrompt?.id == id)
        #expect(viewModel.destinationPrompt?.destination == .prompt)
        #expect(viewModel.destinationOptions.map(\.id) == ["list-groceries"])
        #expect(viewModel.destinationDefaultIdentifier == "list-inbox")
        #expect(viewModel.runErrorMessage == nil, "a successful prompt presentation opens the sheet, not an alert")
    }

    /// The sheet's confirm button runs the checklist once in the chosen list and
    /// clears the pending prompt, without writing the choice back to the store.
    @Test
    func runInDestinationCreatesInChosenListAndClearsThePrompt() async {
        let (store, id) = makeStore(items: ["one"])
        store.setDestination(.prompt, for: id)
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-a", title: "A"), ReminderListOption(id: "list-b", title: "B")],
            defaultIdentifier: "list-a")
        let viewModel = makeViewModel(store: store, targeting: spy)
        let checklist = store.checklist(id: id)!

        await viewModel.run(checklist, in: .list("list-b"))

        #expect(spy.createdTitles == ["one"])
        #expect(spy.createdListIDs == ["list-b"])
        #expect(viewModel.destinationPrompt == nil, "the one-shot choice clears the pending prompt")
        #expect(store.checklist(id: id)?.destination == .prompt, "the choice is never written back to the store")
    }

    /// Sad path: enumerating lists for the prompt throws, so the sheet is never
    /// shown and the permission-denied message appears instead.
    @Test
    func promptRunEnumerationFailureSetsTheErrorMessage() async {
        let (store, id) = makeStore(items: ["one"])
        store.setDestination(.prompt, for: id)
        let targeting = ThrowingListsDestination()
        let viewModel = makeViewModel(store: store, targeting: targeting)

        await viewModel.createReminders(for: id)

        #expect(viewModel.destinationPrompt == nil)
        #expect(viewModel.runErrorMessage == ReminderRunOutcome.permissionDenied.errorMessage)
    }

    /// Sad path: enumerating lists for the prompt yields nothing at all, so the
    /// chooser is never shown with an empty selection — the VM routes to the
    /// missing-destination text instead of raising a bare sheet.
    @Test
    func promptRunWithNoListsRoutesToMissingDestinationText() async {
        let (store, id) = makeStore(items: ["one"])
        store.setDestination(.prompt, for: id)
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(options: [], defaultIdentifier: nil)
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.createReminders(for: id)

        #expect(viewModel.destinationPrompt == nil, "no sheet with nothing to choose")
        #expect(viewModel.destinationOptions.isEmpty)
        #expect(viewModel.runErrorMessage == ReminderRunOutcome.destinationMissing.errorMessage)
    }

    /// Widget deep-link entry point: a `.prompt`, runnable, non-archived id
    /// opens the destination chooser.
    @Test
    func deepLinkPresentsTheChooserForAPromptChecklist() async {
        let (store, id) = makeStore(items: ["one"])
        store.setDestination(.prompt, for: id)
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-inbox", title: "Inbox")],
            defaultIdentifier: "list-inbox")
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.presentDestinationPrompt(forChecklistID: id)

        #expect(viewModel.destinationPrompt?.id == id)
        #expect(viewModel.runErrorMessage == nil)
    }

    /// A non-prompt id must be a no-op: only `.prompt` checklists open the sheet.
    @Test
    func deepLinkIgnoresANonPromptChecklist() async {
        let (store, id) = makeStore(items: ["one"])
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-inbox", title: "Inbox")],
            defaultIdentifier: "list-inbox")
        let viewModel = makeViewModel(store: store, targeting: spy)

        await viewModel.presentDestinationPrompt(forChecklistID: id)

        #expect(viewModel.destinationPrompt == nil)
        #expect(viewModel.destinationOptions.isEmpty)
        #expect(viewModel.runErrorMessage == nil)
    }

    /// The deep-link parser resolves the checklist id from a well-formed
    /// `checkstitch://run?checklist=<uuid>` URL and nothing else.
    @Test(arguments: [
        "file:///tmp/a.json",
        "checkstitch://",
        "checkstitch://run",
        "checkstitch://run?checklist=",
        "checkstitch://run?other=1&checklist=not-a-uuid",
        "https://run?checklist=00000000-0000-0000-0000-000000000000",
    ])
    func deepLinkParserRejectsNonRunURLs(_ urlString: String) {
        #expect(ChecklistRunViewModel.destinationPromptChecklistID(
            from: URL(string: urlString)!) == nil)
    }

    @Test
    func deepLinkParserResolvesAValidRunURL() {
        let id = UUID()
        let url = URL(string: "checkstitch://run?checklist=\(id.uuidString)")!
        #expect(ChecklistRunViewModel.destinationPromptChecklistID(from: url) == id)
    }
}

/// Test double for `ReminderDestinationTargeting` whose `reminderLists()` throws,
/// so the prompt-presentation enumeration failure path is exercised.
@MainActor
private final class ThrowingListsDestination: ReminderDestinationTargeting {
    func requestAccess() async throws -> Bool { true }
    func accessStatus() -> ReminderAccessStatus { .fullAccess }
    func reminderLists() async throws -> ReminderListsSnapshot { throw TestError.boom }
    func create(title: String, notes: String?, priority: ChecklistItemPriority,
                in list: ReminderListOption, dueDateComponents: DateComponents?) async throws {}
}
