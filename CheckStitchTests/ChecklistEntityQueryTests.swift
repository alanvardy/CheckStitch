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

    /// `entities(for:)` returns matches in the store's display order, not the
    /// order of the requested identifiers.
    @Test
    func entitiesForIdentifiersReturnsStoreDisplayOrder() async throws {
        let store = makeStore()
        let query = ChecklistEntityQuery(store: store)
        let reversed = store.checklists.reversed().map { $0.id.uuidString }

        let entities = try await query.entities(for: reversed)

        #expect(entities.map(\.name) == ["Groceries", "Packing", "Chores"])
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

    @Test
    func entitiesForIdentifiersExcludeArchived() async throws {
        let store = ChecklistStore(defaults: makeIsolatedDefaults())
        let active = store.create(name: "Groceries")
        let archived = store.create(name: "Packing")
        store.archive(id: archived.id)
        let query = ChecklistEntityQuery(store: store)

        let entities = try await query.entities(for: [active.id.uuidString, archived.id.uuidString])

        #expect(entities.map(\.name) == ["Groceries"])
    }

    /// `entities(matching:)` must not offer archived checklists to Siri.
    @Test
    func entitiesMatchingExcludesArchived() async throws {
        let store = ChecklistStore(defaults: makeIsolatedDefaults())
        _ = store.create(name: "Groceries")
        let archived = store.create(name: "Packing")
        store.archive(id: archived.id)
        let query = ChecklistEntityQuery(store: store)

        let entities = try await query.entities(matching: "PACK")

        #expect(entities.isEmpty)
    }

    @Test
    func suggestedEntitiesExcludesArchived() async throws {
        let store = ChecklistStore(defaults: makeIsolatedDefaults())
        store.create(name: "Groceries")
        let archived = store.create(name: "Packing")
        store.archive(id: archived.id)
        let query = ChecklistEntityQuery(store: store)

        let entities = try await query.suggestedEntities()

        #expect(entities.map(\.name) == ["Groceries"])
    }

    // MARK: ReminderListEntityQuery

    /// Full-access enumeration offers the synthetic default plus every selectable
    /// Reminders list (non-default lists, matching `ReminderListsSnapshot`).
    @Test
    func reminderListSuggestedEntitiesEnumeratesSelectableListsPlusDefault() async throws {
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-1", title: "Groceries")],
            defaultIdentifier: nil)
        let query = ReminderListEntityQuery(targeting: spy)

        let entities = try await query.suggestedEntities()

        #expect(entities.map(\.id) == [ReminderListEntity.defaultID, "list-1"])
        #expect(entities.first?.name == "Default (Inbox)")
        #expect(entities[1].name == "Groceries")
    }

    @Test
    func reminderListQueryFiltersByIdentifiers() async throws {
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-1", title: "Groceries")],
            defaultIdentifier: nil)
        let query = ReminderListEntityQuery(targeting: spy)

        let entities = try await query.entities(for: ["list-1", "ghost"])

        #expect(entities.map(\.id) == ["list-1"])
    }

    /// A denied/notDetermined read degrades to the synthetic default only — the
    /// query never prompts from inside a Siri/Shortcuts context.
    @Test(arguments: [ReminderAccessStatus.notDetermined, ReminderAccessStatus.denied])
    func unauthorizedReminderListQueryReturnsOnlySyntheticDefault(_ status: ReminderAccessStatus) async throws {
        let spy = SpyReminderDestination()
        spy.accessStatusValue = status
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-1", title: "Groceries")],
            defaultIdentifier: nil)
        let query = ReminderListEntityQuery(targeting: spy)

        let entities = try await query.suggestedEntities()

        #expect(entities.map(\.id) == [ReminderListEntity.defaultID])
    }

    /// The system default list is represented once by the synthetic default; the
    /// concrete default calendar is filtered out of the selectable options.
    @Test
    func reminderListQueryOmitsTheConcreteDefaultFromSelectableOptions() async throws {
        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "default-cal", title: "Reminders"),
                      ReminderListOption(id: "list-1", title: "Groceries")],
            defaultIdentifier: "default-cal")
        let query = ReminderListEntityQuery(targeting: spy)

        let entities = try await query.suggestedEntities()

        #expect(entities.map(\.id) == [ReminderListEntity.defaultID, "list-1"])
    }
}
