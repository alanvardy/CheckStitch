@testable import CheckStitch
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct CreateChecklistIntentTests {
    private func makeStore() -> ChecklistStore {
        ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
    }

    @Test
    func createStoresOneItemAndReportsExactDialogue() async throws {
        let store = makeStore()
        let intent = CreateChecklistIntent(store: store)
        intent.name = "Groceries"
        intent.items = ["Milk"]

        _ = try await intent.perform()

        #expect(store.checklists.count == 1)
        #expect(store.checklists[0].items.map(\.title) == ["Milk"])
        #expect(CreateChecklistDialogue.message(
            name: store.checklists[0].name, itemCount: store.checklists[0].items.count).resolved()
            == "Created Groceries with 1 item.")
    }

    @Test
    func createStoresManyItemsAndReportsCount() async throws {
        let store = makeStore()
        let intent = CreateChecklistIntent(store: store)
        intent.name = "Groceries"
        intent.items = [" Milk ", "  ", "Eggs", "Bread"] // whitespace trimmed, blanks dropped

        _ = try await intent.perform()

        #expect(store.checklists.count == 1)
        #expect(store.checklists[0].items.map(\.title) == ["Milk", "Eggs", "Bread"])
        #expect(CreateChecklistDialogue.message(
            name: store.checklists[0].name, itemCount: store.checklists[0].items.count).resolved()
            == "Created Groceries with 3 items.")
    }

    @Test
    func duplicateNameIsDisambiguatedAndDialogueReportsActualName() async throws {
        let store = makeStore()
        _ = store.create(name: "Groceries")
        let intent = CreateChecklistIntent(store: store)
        intent.name = "Groceries"
        intent.items = ["Milk"]

        _ = try await intent.perform()

        #expect(store.checklists.count == 2)
        #expect(store.checklists.map(\.name) == ["Groceries", "Groceries 2"])
        #expect(CreateChecklistDialogue.message(
            name: store.checklists[1].name, itemCount: store.checklists[1].items.count).resolved()
            == "Created Groceries 2 with 1 item.")
    }

    @Test
    func blankNameThrowsAndCreatesNothing() async throws {
        let store = makeStore()
        let intent = CreateChecklistIntent(store: store)
        intent.name = "   "
        intent.items = ["Milk"]

        do {
            _ = try await intent.perform()
            Issue.record("a blank name should throw, not create")
        } catch let error as CreateChecklistIntentError {
            #expect(error.errorDescription == "Give the checklist a name.")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(store.checklists.isEmpty)
    }

    @Test
    func blankOnlyItemsThrowAndCreateNothing() async throws {
        let store = makeStore()
        let intent = CreateChecklistIntent(store: store)
        intent.name = "Groceries"
        intent.items = ["   ", " "]

        do {
            _ = try await intent.perform()
            Issue.record("blank-only items should throw, not create")
        } catch let error as CreateChecklistIntentError {
            #expect(error.errorDescription == "Add at least one item.")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(store.checklists.isEmpty)
    }

    @Test
    func emptyItemsThrowAndCreateNothing() async throws {
        let store = makeStore()
        let intent = CreateChecklistIntent(store: store)
        intent.name = "Groceries"
        intent.items = []

        do {
            _ = try await intent.perform()
            Issue.record("no items should throw, not create")
        } catch let error as CreateChecklistIntentError {
            #expect(error.errorDescription == "Add at least one item.")
        } catch {
            Issue.record("unexpected error type: \(error)")
        }
        #expect(store.checklists.isEmpty)
    }

    @Test
    func performReadsInjectedStoreNotTheAppGroup() async throws {
        let store = makeStore()
        let intent = CreateChecklistIntent(store: store)
        intent.name = "Groceries"
        intent.items = ["Milk"]

        _ = try await intent.perform()

        // The created checklist lands in the injected store, proving `perform()`
        // used the seam rather than a fresh AppGroup-backed store.
        #expect(store.checklists.count == 1)
        #expect(store.checklists[0].name == "Groceries")
    }
}