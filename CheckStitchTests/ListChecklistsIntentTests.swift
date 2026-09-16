@testable import CheckStitch
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ListChecklistsIntentTests {
    /// A store holding Groceries, Packing, Chores in display order.
    private func makeStore(defaults: UserDefaults = makeIsolatedDefaults()) -> ChecklistStore {
        let store = ChecklistStore(defaults: defaults)
        store.create(name: "Groceries")
        store.create(name: "Packing")
        store.create(name: "Chores")
        return store
    }

    @Test
    func listsNamesInDisplayOrderWithExactDialogue() {
        let store = makeStore()

        let dialogue = ListChecklistsDialogue.message(for: store.checklists.map(\.name))

        #expect(dialogue.resolved() == "You have 3 checklists: Groceries, Packing, Chores.")
    }

    @Test
    func emptyStoreReportsEmptyState() {
        let dialogue = ListChecklistsDialogue.message(for: [])

        #expect(dialogue.resolved() == "You don't have any checklists yet.")
    }

    /// The query path builds a fresh store from the injected defaults and
    /// never writes: checklists and the persisted payload are byte-identical
    /// before and after `perform()`.
    @Test
    func performDoesNotMutateStore() async throws {
        let defaults = makeIsolatedDefaults()
        let store = makeStore(defaults: defaults)
        let before = store.checklists
        let key = "checklists.v1"
        let persistedBefore = try #require(defaults.data(forKey: key))

        let intent = ListChecklistsIntent(store: store)
        _ = try await intent.perform()

        #expect(store.checklists == before)
        #expect(defaults.data(forKey: key) == persistedBefore)
    }
}