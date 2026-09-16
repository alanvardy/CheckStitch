@testable import CheckStitch
@testable import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistEntityQueryTests {
    /// Store in display order: Groceries, Packing, Chores.
    private func makeStore() -> ChecklistStore {
        let store = ChecklistStore(defaults: makeIsolatedDefaults())
        store.create(name: "Groceries")
        store.create(name: "Packing")
        store.create(name: "Chores")
        return store
    }

    @Test
    func suggestedEntitiesListsAllChecklistsInDisplayOrder() async throws {
        let store = makeStore()
        let query = ChecklistEntityQuery(store: store)

        let entities = try await query.suggestedEntities()

        #expect(entities.map(\.name) == ["Groceries", "Packing", "Chores"])
        #expect(entities.map(\.id) == store.checklists.map { $0.id.uuidString })
    }

    @Test
    func entitiesForIdentifiersReturnsOnlyMatching() async throws {
        let store = makeStore()
        let query = ChecklistEntityQuery(store: store)
        let wanted = store.checklists[0].id.uuidString

        let entities = try await query.entities(for: [wanted, UUID().uuidString])

        #expect(entities.map(\.name) == ["Groceries"])
        #expect(entities[0].id == wanted)
    }

    @Test
    func entitiesMatchingFiltersByNameCaseInsensitively() async throws {
        let store = makeStore()
        let query = ChecklistEntityQuery(store: store)

        let entities = try await query.entities(matching: "PACK")

        #expect(entities.map(\.name) == ["Packing"])
    }

    @Test
    func renamingKeepsEntityIdentity() async throws {
        let store = makeStore()
        let original = store.checklists[0]
        store.rename(id: original.id, to: "Market")
        let query = ChecklistEntityQuery(store: store)

        let entities = try await query.suggestedEntities()

        let renamed = try #require(entities.first { $0.name == "Market" })
        #expect(renamed.id == original.id.uuidString)
    }

    @Test
    func emptyStoreYieldsNoEntities() async throws {
        let store = ChecklistStore(defaults: makeIsolatedDefaults())
        let query = ChecklistEntityQuery(store: store)

        let entities = try await query.suggestedEntities()

        #expect(entities.isEmpty)
    }
}
