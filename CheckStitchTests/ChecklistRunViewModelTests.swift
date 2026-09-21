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
                               targeting: SpyReminderDestination,
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
}