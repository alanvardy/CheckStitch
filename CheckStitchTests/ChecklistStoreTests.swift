import XCTest
@testable import CheckStitch
import CheckStitchCore

@MainActor
final class ChecklistStoreTests: XCTestCase {
    private let key = "checklists.v1"

    /// Fresh, uniquely-named suite per test so tests cannot bleed into each other.
    private func makeDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "test.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("could not create test UserDefaults suite \(suiteName)")
        }
        return (defaults, suiteName)
    }

    /// Synchronous text-edit persistence — tests assert on disk right after a
    /// mutation, so the production debounce is opted out of. The debounce
    /// itself is covered by the two dedicated tests at the bottom.
    private func makeStore(defaults: UserDefaults) -> ChecklistStore {
        ChecklistStore(defaults: defaults, key: key, textEditDelay: nil)
    }

    /// A checklist named "Groceries" whose items carry the given titles in
    /// order — the smallest fixture that exercises reordering.
    private func makeItemStore(defaults: UserDefaults, titles: [String]) -> (store: ChecklistStore, checklistID: UUID) {
        let store = makeStore(defaults: defaults)
        let checklistID = store.create(name: "Groceries").id
        for title in titles {
            store.addItem(to: checklistID)
            let items = store.checklist(id: checklistID)?.items
            store.updateItem(checklistID: checklistID, itemID: items?.last?.id ?? UUID(), title: title)
        }
        return (store: store, checklistID: checklistID)
    }

    /// Deterministic clock so revision/timestamp assertions are exact.
    private final class Clock { var now = Date(timeIntervalSince1970: 0) }

    func testCreatePersistsAcrossReload() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.rename(id: created.id, to: "Groceries")

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 1)
        XCTAssertEqual(reloaded.checklists.first?.id, created.id)
        XCTAssertEqual(reloaded.checklists.first?.name, "Groceries")

        // The payload on disk is a versioned envelope, not a bare array.
        let data = try? XCTUnwrap(suite.defaults.data(forKey: key))
        XCTAssertEqual(ChecklistCodec.decode(data ?? Data()).count, 1)
    }

    func testRenamePersists() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.rename(id: created.id, to: "Chores")

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.name, "Chores")
    }

    func testAddAndRemoveItemPersists() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        store.addItem(to: created.id)
        let items = try? XCTUnwrap(store.checklist(id: created.id)?.items)
        store.updateItem(checklistID: created.id, itemID: items?[1].id ?? UUID(), title: "Milk")
        store.removeItems(from: created.id, at: IndexSet(integer: 0))

        let reloaded = makeStore(defaults: suite.defaults)
        let reloadedItems = reloaded.checklist(id: created.id)?.items
        XCTAssertEqual(reloadedItems?.count, 1)
        XCTAssertEqual(reloadedItems?.first?.title, "Milk")
    }

    func testDeleteRemovesOnlyTarget() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let first = store.create(name: "Groceries")
        let second = store.create(name: "Chores")
        store.delete(id: first.id)

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 1)
        XCTAssertEqual(reloaded.checklists.first?.id, second.id)
        XCTAssertNil(reloaded.checklist(id: first.id))
    }

    func testDeleteUnknownIDIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.delete(id: UUID())

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.map(\.id), [created.id])
    }

    func testCorruptDataYieldsEmpty() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        suite.defaults.set(Data("not json".utf8), forKey: key)

        let store = makeStore(defaults: suite.defaults)
        XCTAssertTrue(store.checklists.isEmpty)
    }

    func testCorruptPayloadIsRepairedOnSave() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        suite.defaults.set(Data("not json".utf8), forKey: key)

        let store = makeStore(defaults: suite.defaults)
        store.create()

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 1)
    }

    func testUnsupportedVersionPayloadIsNotOverwritten() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let newer = Data(#"{"version":99,"checklists":[]}"#.utf8)
        suite.defaults.set(newer, forKey: key)

        let store = makeStore(defaults: suite.defaults)
        XCTAssertTrue(store.checklists.isEmpty)
        store.create(name: "Groceries")
        store.create(name: "Chores")

        // The newer payload survives; the in-memory changes are simply not persisted.
        XCTAssertEqual(suite.defaults.data(forKey: key), newer)
    }

    func testTextEditsAreCoalescedUntilFlush() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: .milliseconds(50))
        let created = store.create()

        store.rename(id: created.id, to: "G")
        store.rename(id: created.id, to: "Gr")
        store.rename(id: created.id, to: "Groceries")

        // The in-memory value is current, but the debounce window is still open.
        XCTAssertEqual(store.checklist(id: created.id)?.name, "Groceries")
        XCTAssertEqual(makeStore(defaults: suite.defaults).checklist(id: created.id)?.name, "New checklist")

        store.flushPendingSave()

        XCTAssertEqual(makeStore(defaults: suite.defaults).checklist(id: created.id)?.name, "Groceries")
    }

    func testStructuralSaveCancelsPendingTextEdit() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: .seconds(30))
        let created = store.create()
        store.rename(id: created.id, to: "Groceries")
        store.addItem(to: created.id)

        // The structural save persists the pending rename too, and the queued
        // write can no longer land afterwards.
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.name, "Groceries")
        XCTAssertEqual(reloaded.checklist(id: created.id)?.items.count, 1)
    }

    // MARK: - Create uniqueness

    func testRepeatedDefaultCreatesIncrementTheName() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let first = store.create()
        let second = store.create()
        let third = store.create()

        // A second "New checklist" is disambiguated instead of refused.
        XCTAssertEqual(first.name, "New checklist")
        XCTAssertEqual(second.name, "New checklist 2")
        XCTAssertEqual(third.name, "New checklist 3")
        XCTAssertEqual(store.checklists.count, 3)

        // The disambiguated names survive a reload unchanged.
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["New checklist", "New checklist 2", "New checklist 3"])
    }

    func testCreateReusesAGapLeftByADeletedChecklist() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()
        let second = store.create()
        store.delete(id: second.id)

        // With "New checklist 2" free again, the next create takes the lowest
        // free suffix rather than skipping to 3.
        let recreated = store.create()
        XCTAssertEqual(recreated.name, "New checklist 2")
        XCTAssertEqual(store.checklists.map(\.name), ["New checklist", "New checklist 2"])
    }

    func testCreateWithTypedNameSucceeds() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create(name: "Groceries")
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertEqual(store.checklist(id: created.id)?.name, "Groceries")
    }

    func testCreateWithDuplicateTypedNameIncrements() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create(name: "Groceries")

        // Case-insensitive collision: the requested casing is kept and a
        // numeric suffix disambiguates.
        let second = store.create(name: "groceries")
        XCTAssertEqual(second.name, "groceries 2")

        // A whitespace-padded duplicate is trimmed before the suffix is added,
        // and steps past the suffix already in use.
        let third = store.create(name: "  GROCERIES  ")
        XCTAssertEqual(third.name, "GROCERIES 3")

        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "groceries 2", "GROCERIES 3"])
    }

    // MARK: - Rename uniqueness

    func testRenameToUniqueNameSucceeds() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create(name: "Groceries")
        XCTAssertEqual(store.rename(id: created.id, to: "Errands"), .renamed)
        XCTAssertEqual(store.checklist(id: created.id)?.name, "Errands")
    }

    func testRenameKeepingOwnNameIsAllowed() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create(name: "Groceries")
        // The checklist being renamed is excluded, so keeping its own name —
        // including a case/whitespace variant of it — is never a conflict.
        XCTAssertEqual(store.rename(id: created.id, to: "Groceries"), .renamed)
        XCTAssertEqual(store.rename(id: created.id, to: "  groceries  "), .renamed)
        XCTAssertEqual(store.checklist(id: created.id)?.name, "  groceries  ")
    }

    func testRenameToAnotherChecklistsNameIsRejected() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create(name: "Groceries")
        let chores = store.create(name: "Chores")

        // A case variant and a trimmed variant of the other name are refused
        // and change nothing, so a reload still sees the pre-rename state.
        XCTAssertEqual(store.rename(id: chores.id, to: "GROCERIES"), .nameTaken)
        XCTAssertEqual(store.checklist(id: chores.id)?.name, "Chores")

        XCTAssertEqual(store.rename(id: chores.id, to: "  groceries  "), .nameTaken)
        XCTAssertEqual(store.checklist(id: chores.id)?.name, "Chores")

        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Chores"])
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["Groceries", "Chores"])
    }

    func testRenameUnknownIDReportsNotFound() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        XCTAssertEqual(store.rename(id: UUID(), to: "Groceries"), .notFound)
    }

    func testLegacyPayloadIsMigratedAndSavable() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        // A true v1 payload: v1 carried no sync state, so migration stamps it.
        let legacy = Data(#"{"version":1,"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk"}]}]}"#.utf8)
        suite.defaults.set(legacy, forKey: key)

        let store = makeStore(defaults: suite.defaults)
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertEqual(store.checklists.first?.revision, 1)
        XCTAssertEqual(store.checklists.first?.items.first?.revision, 1)
        // Ordering is seeded from the record's own sync state, granting no win.
        XCTAssertEqual(store.checklists.first?.orderRevision, 1)
        XCTAssertEqual(store.checklists.first?.itemOrder, store.checklists.first?.items.map(\.id))

        // The migrated payload is savable, not stalled in memory.
        store.create()

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 2)
        XCTAssertEqual(reloaded.checklists.first?.name, "Groceries")
    }

    func testDeviceIDIsStableAcrossInstances() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let first = makeStore(defaults: suite.defaults)
        let second = makeStore(defaults: suite.defaults)
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertFalse(first.deviceID.isEmpty)
    }

    func testNewPayloadIsVersionThree() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()

        let data = try? XCTUnwrap(suite.defaults.data(forKey: key))
        guard case .loaded(let stored) = ChecklistCodec.classify(data ?? Data()) else {
            XCTFail("expected the stored payload to classify as loaded")
            return
        }
        XCTAssertEqual(stored.version, 3)
    }

    /// A stored v2 payload has real sync state. It must load with its revision,
    /// timestamp and tombstones intact, stay writable, and never be restamped.
    func testV2PayloadLoadsVerbatimWithoutRestamping() throws {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let itemID = UUID()
        let modifiedAt = Date(timeIntervalSince1970: 1_234)
        let payload = ChecklistEnvelope(
            version: 2,
            deviceID: "remote-device",
            checklists: [Checklist(
                name: "Groceries",
                items: [ChecklistItem(id: itemID, title: "Milk", modifiedAt: modifiedAt, revision: 7)],
                modifiedAt: modifiedAt,
                revision: 9)],
            tombstones: [ChecklistTombstone(
                checklistID: UUID(), itemID: nil, deletedAt: modifiedAt, revision: 2)])
        suite.defaults.set(try ChecklistCodec.encode(payload), forKey: key)

        let store = makeStore(defaults: suite.defaults)
        XCTAssertTrue(store.canAcceptRemoteChanges, "a migrated v2 payload stays writable")
        XCTAssertEqual(store.checklists.first?.revision, 9, "v2 revisions must not be restamped")
        XCTAssertEqual(store.checklists.first?.modifiedAt, modifiedAt)
        XCTAssertEqual(store.checklists.first?.items.first?.revision, 7)
        XCTAssertEqual(store.tombstones.count, 1, "v2 tombstones must survive migration")

        // Persist and reload: still not restamped.
        store.create()
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.first(where: { $0.name == "Groceries" })?.revision, 9)
        XCTAssertEqual(reloaded.tombstones.count, 1)
    }

    func testMutationsStampRevisionAndTimestamp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let clock = Clock()
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })

        let created = store.create()
        XCTAssertEqual(created.revision, 1)
        XCTAssertEqual(created.modifiedAt, clock.now)

        clock.now = Date(timeIntervalSince1970: 1_000)
        store.rename(id: created.id, to: "Groceries")
        XCTAssertEqual(store.checklist(id: created.id)?.revision, 2)
        XCTAssertEqual(store.checklist(id: created.id)?.modifiedAt, clock.now)

        store.addItem(to: created.id)
        let item = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(item?.revision, 1)
        XCTAssertEqual(item?.modifiedAt, clock.now)

        store.updateItem(checklistID: created.id, itemID: item?.id ?? UUID(), title: "Milk")
        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.revision, 2)
    }

    func testDescriptionEditBumpsItemRevisionNotChecklist() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        let item = store.checklist(id: created.id)?.items.first

        clock.now = Date(timeIntervalSince1970: 1_000)
        store.updateItemDescription(checklistID: created.id, itemID: item?.id ?? UUID(), description: "2 litres")

        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.description, "2 litres")
        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.revision, 2)     // 1 on add, +1
        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.modifiedAt, clock.now)
        XCTAssertEqual(store.checklist(id: created.id)?.revision, 1)                 // checklist untouched
        XCTAssertEqual(store.checklist(id: created.id)?.modifiedAt, created.modifiedAt)
    }

    func testDescriptionEditPersistsAndReloads() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        let item = store.checklist(id: created.id)?.items.first
        store.updateItemDescription(checklistID: created.id, itemID: item?.id ?? UUID(), description: "2 litres")

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.items.first?.description, "2 litres")
    }

    func testTitleEditLeavesDescriptionIntact() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        let id = store.checklist(id: created.id)?.items.first?.id ?? UUID()
        store.updateItemDescription(checklistID: created.id, itemID: id, description: "2 litres")
        store.updateItem(checklistID: created.id, itemID: id, title: "Milk")

        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.title, "Milk")
        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.description, "2 litres")
    }

    func testDuplicateCopiesDescription() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")
        store.addItem(to: source.id)
        let item = store.checklist(id: source.id)?.items.first
        store.updateItemDescription(checklistID: source.id, itemID: item?.id ?? UUID(), description: "2 litres")

        let copy = store.duplicate(id: source.id, name: "Groceries copy")

        XCTAssertEqual(copy?.items.first?.description, "2 litres")
        XCTAssertEqual(copy?.items.first?.revision, 1)          // fresh copy, not source's 2
        XCTAssertNotEqual(copy?.items.first?.id, item?.id)
    }

    /// Sad path: unknown ids are silent no-ops, exactly like `updateItem`.
    func testDescriptionEditUnknownIDsIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)

        store.updateItemDescription(checklistID: created.id, itemID: UUID(), description: "ghost")
        store.updateItemDescription(checklistID: UUID(), itemID: UUID(), description: "ghost")

        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.description, "")
    }

    // MARK: - moveItems

    func testMoveReordersItemsWithinList() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let (store, checklistID) = makeItemStore(defaults: suite.defaults, titles: ["A", "B", "C"])
        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: 2)

        let moved = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertEqual(moved?.items.map(\.title), ["B", "A", "C"])
        XCTAssertEqual(moved?.itemOrder, moved?.items.map(\.id))
    }

    func testMoveToEnd() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let (store, checklistID) = makeItemStore(defaults: suite.defaults, titles: ["A", "B", "C"])
        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: 3)

        let moved = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertEqual(moved?.items.map(\.title), ["B", "C", "A"])
    }

    func testMoveOutOfRangeIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let (store, checklistID) = makeItemStore(defaults: suite.defaults, titles: ["A", "B", "C"])
        let before = try? XCTUnwrap(suite.defaults.data(forKey: key))
        let orderRevision = store.checklist(id: checklistID)?.orderRevision ?? -1

        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 9), to: 0)
        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: -1)
        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: 99)

        let after = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertEqual(after?.items.map(\.title), ["A", "B", "C"])
        XCTAssertEqual(after?.itemOrder, after?.items.map(\.id) ?? [])
        XCTAssertEqual(after?.orderRevision, orderRevision)
        XCTAssertEqual(suite.defaults.data(forKey: key), before)
    }

    func testMoveUnknownChecklistIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let (store, checklistID) = makeItemStore(defaults: suite.defaults, titles: ["A", "B"])
        let before = try? XCTUnwrap(suite.defaults.data(forKey: key))

        store.moveItems(checklistID: UUID(), from: IndexSet(integer: 0), to: 1)

        XCTAssertEqual(store.checklists.map(\.id), [checklistID])
        XCTAssertEqual(suite.defaults.data(forKey: key), before)
    }

    func testMovePreservesItemIdentity() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let clock = Clock()
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let checklistID = store.create(name: "Groceries").id
        store.addItem(to: checklistID)
        store.addItem(to: checklistID)
        let initial = try? XCTUnwrap(store.checklist(id: checklistID)?.items)
        store.updateItem(checklistID: checklistID, itemID: initial?[0].id ?? UUID(), title: "A")
        store.updateItem(checklistID: checklistID, itemID: initial?[1].id ?? UUID(), title: "B")

        clock.now = Date(timeIntervalSince1970: 5_000)
        let before = try? XCTUnwrap(store.checklist(id: checklistID))
        let beforeItems = before?.items ?? []

        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: 1)

        let after = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertEqual(after?.name, before?.name)
        XCTAssertEqual(after?.revision, before?.revision)
        XCTAssertEqual(after?.modifiedAt, before?.modifiedAt)
        let afterByID = Dictionary(uniqueKeysWithValues: (after?.items ?? []).map { ($0.id, $0) })
        for item in beforeItems {
            XCTAssertEqual(afterByID[item.id]?.id, item.id)
            XCTAssertEqual(afterByID[item.id]?.title, item.title, "item \(item.title) kept its text")
            XCTAssertEqual(afterByID[item.id]?.modifiedAt, item.modifiedAt)
            XCTAssertEqual(afterByID[item.id]?.revision, item.revision)
        }
        XCTAssertEqual(after?.orderRevision, (before?.orderRevision ?? 0) + 1)
        XCTAssertEqual(after?.orderModifiedAt, clock.now)
    }

    func testMoveStampsOrderNotChecklist() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 1_000)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let checklistID = store.create(name: "Groceries").id
        store.addItem(to: checklistID)
        store.addItem(to: checklistID)
        let created = try? XCTUnwrap(store.checklist(id: checklistID))

        clock.now = Date(timeIntervalSince1970: 2_000)
        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: 1)

        let moved = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertEqual(moved?.orderRevision, (created?.orderRevision ?? 0) + 1)
        XCTAssertEqual(moved?.orderModifiedAt, clock.now)
        XCTAssertEqual(moved?.revision, created?.revision, "a reorder is not a checklist edit")
        XCTAssertEqual(moved?.modifiedAt, created?.modifiedAt)
    }

    func testMovePersistsAcrossReload() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let (store, checklistID) = makeItemStore(defaults: suite.defaults, titles: ["A", "B", "C"])
        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: 2)

        let reloaded = makeStore(defaults: suite.defaults)
        let items = try? XCTUnwrap(reloaded.checklist(id: checklistID)?.items)
        XCTAssertEqual(items?.map(\.title), ["B", "A", "C"])
        XCTAssertEqual(reloaded.checklist(id: checklistID)?.orderRevision, 1)
    }

    // MARK: - itemOrder lockstep

    func testAddItemAppendsToItemOrder() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let checklistID = store.create().id
        store.addItem(to: checklistID)

        let checklist = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertEqual(checklist?.itemOrder, checklist?.items.map(\.id))
        XCTAssertEqual(checklist?.itemOrder.last, checklist?.items.last?.id)
    }

    func testRemoveItemsDropsFromItemOrder() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let (store, checklistID) = makeItemStore(defaults: suite.defaults, titles: ["A", "B", "C"])
        let removedID = store.checklist(id: checklistID)?.items[1].id ?? UUID()
        store.removeItems(from: checklistID, at: IndexSet(integer: 1))

        let checklist = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertFalse(checklist?.itemOrder.contains(where: { $0 == removedID }) ?? false)
        XCTAssertEqual(checklist?.itemOrder, checklist?.items.map(\.id) ?? [])
    }

    func testApplyKeepsItemsAndItemOrderInLockstep() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let (store, checklistID) = makeItemStore(defaults: suite.defaults, titles: ["A", "B"])

        // Remote reorders the checklist with its own winning order metadata and
        // adds a remote-only item; the merged list stays canonical.
        let remoteItem = ChecklistItem(title: "Remote", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [Checklist(
                id: checklistID,
                name: "Groceries",
                items: [remoteItem],
                modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 2,
                itemOrder: [remoteItem.id],
                orderRevision: 2, orderModifiedAt: Date(timeIntervalSince1970: 5_000))])

        XCTAssertTrue(store.apply(remote: remote))
        let merged = try? XCTUnwrap(store.checklist(id: checklistID))
        XCTAssertEqual(merged?.itemOrder, merged?.items.map(\.id) ?? [])
        XCTAssertEqual(merged?.items.map(\.title), ["Remote", "A", "B"])

        // The identical remote payload is a no-op the second time.
        XCTAssertFalse(store.apply(remote: remote))
    }

    func testDeleteLeavesChecklistTombstone() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.delete(id: created.id)

        XCTAssertEqual(store.tombstones.count, 1)
        XCTAssertEqual(store.tombstones.first?.checklistID, created.id)
        XCTAssertNil(store.tombstones.first?.itemID)
        XCTAssertEqual(store.tombstones.first?.revision, 2)
        XCTAssertTrue(store.checklists.isEmpty)

        // The tombstone survives a reload.
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.tombstones.count, 1)
        XCTAssertEqual(reloaded.tombstones.first?.checklistID, created.id)
        XCTAssertNil(reloaded.tombstones.first?.itemID)
    }

    func testRemoveItemsLeavesItemTombstones() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        store.addItem(to: created.id)
        let items = try? XCTUnwrap(store.checklist(id: created.id)?.items)

        store.removeItems(from: created.id, at: IndexSet(integer: 1))
        store.removeItems(from: created.id, at: IndexSet(integer: 0))

        XCTAssertEqual(store.tombstones.count, 2)
        XCTAssertEqual(store.checklist(id: created.id)?.items.count, 0)
        let tombstoneIDs = store.tombstones.map(\.itemID)
        XCTAssertTrue(tombstoneIDs.contains(items?[0].id ?? UUID()))
        XCTAssertTrue(tombstoneIDs.contains(items?[1].id ?? UUID()))

        // Reload preserves the item tombstones.
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.tombstones.count, 2)
    }

    func testApplyMergesRemoteChecklist() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Remote", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])

        XCTAssertTrue(store.apply(remote: remote))
        XCTAssertEqual(store.checklists.count, 2)
        XCTAssertEqual(store.checklists.map(\.name), ["New checklist", "Remote"])

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 2)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["New checklist", "Remote"])
    }

    func testApplyPropagatesRemoteTombstone() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [],
            tombstones: [ChecklistTombstone(
                checklistID: created.id, itemID: nil,
                deletedAt: Date(timeIntervalSince1970: 9_999), revision: 1)])

        XCTAssertTrue(store.apply(remote: remote))
        XCTAssertTrue(store.checklists.isEmpty)
        XCTAssertEqual(store.tombstones.count, 1)
        XCTAssertEqual(store.tombstones.first?.checklistID, created.id)
    }

    func testApplyIsIdempotent() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()
        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Remote", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])

        XCTAssertTrue(store.apply(remote: remote))
        let storedAfterFirst = try? XCTUnwrap(suite.defaults.data(forKey: key))

        XCTAssertFalse(store.apply(remote: remote))
        XCTAssertEqual(suite.defaults.data(forKey: key), storedAfterFirst)
    }

    func testApplyRefusesFutureVersion() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        let stored = try? XCTUnwrap(suite.defaults.data(forKey: key))
        let future = ChecklistEnvelope(
            version: 99,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Future", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])

        XCTAssertFalse(store.apply(remote: future))
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertEqual(store.checklists.first?.id, created.id)
        XCTAssertTrue(store.tombstones.isEmpty)
        XCTAssertEqual(suite.defaults.data(forKey: key), stored)
    }

    func testEnvelopeRoundTripsThroughCodec() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()

        let encoded = try? XCTUnwrap(ChecklistCodec.encode(store.envelope))
        XCTAssertEqual(ChecklistCodec.classify(encoded ?? Data()), .loaded(store.envelope))
    }

    func testOnChangeFiresForLocalSavesButNotWhenApplyingRemote() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        var changes = 0
        store.onChange = { changes += 1 }

        store.create()
        XCTAssertEqual(changes, 1, "a local save notifies the sync coordinator")

        let remote = ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "other-device",
            checklists: [Checklist(id: UUID(), name: "Remote", modifiedAt: Date(timeIntervalSince1970: 5_000), revision: 1)])
        XCTAssertTrue(store.apply(remote: remote))
        XCTAssertEqual(changes, 1, "applying remote state must not schedule a push back to the cloud")
    }

    // MARK: - Duplicate

    func testDuplicateCopiesItemsWithFreshIdentifiersAndRevisions() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")
        store.addItem(to: source.id)
        let item = store.checklist(id: source.id)?.items.first
        store.updateItem(checklistID: source.id, itemID: item?.id ?? UUID(), title: "Milk")

        let copy = store.duplicate(id: source.id, name: ChecklistStore.duplicateName(basedOn: "Groceries"))

        let duplicated = try? XCTUnwrap(copy)
        XCTAssertEqual(duplicated?.items.map(\.title), ["Milk"])
        XCTAssertEqual(duplicated?.revision, 1)
        XCTAssertEqual(duplicated?.items.first?.revision, 1)          // fresh, not the source's 2
        XCTAssertNotEqual(duplicated?.items.first?.id, item?.id)      // never a reused id
        XCTAssertNotEqual(duplicated?.id, source.id)
        XCTAssertEqual(store.checklist(id: source.id)?.items.first?.revision, 2)  // source untouched
    }

    func testDuplicateDisambiguatesTheCopyName() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")

        // "Groceries copy", "Groceries copy 2", "Groceries copy 3"
        let first = store.duplicate(id: source.id, name: ChecklistStore.duplicateName(basedOn: "Groceries"))
        let second = store.duplicate(id: source.id, name: ChecklistStore.duplicateName(basedOn: "Groceries"))
        let third = store.duplicate(id: source.id, name: ChecklistStore.duplicateName(basedOn: "Groceries"))
        XCTAssertEqual(first?.name, "Groceries copy")
        XCTAssertEqual(second?.name, "Groceries copy 2")
        XCTAssertEqual(third?.name, "Groceries copy 3")

        // and a user-typed taken name -> "Groceries 2"
        let typed = store.duplicate(id: source.id, name: "Groceries")
        XCTAssertEqual(typed?.name, "Groceries 2")
        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Groceries copy", "Groceries copy 2", "Groceries copy 3", "Groceries 2"])
    }

    func testDuplicateNameIsSourceNamePlusCopy() {
        XCTAssertEqual(ChecklistStore.duplicateName(basedOn: "Groceries"), "Groceries copy")
    }

    func testDuplicateBlankNameFallsBackToTheDefault() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")

        let copy = store.duplicate(id: source.id, name: "   ")
        XCTAssertEqual(copy?.name, "Groceries copy", "a blank name falls back to the default, never \"\"")
    }

    func testDuplicateNewlineOnlyNameFallsBackToTheDefault() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")

        let copy = store.duplicate(id: source.id, name: "\n\t\n")
        XCTAssertEqual(copy?.name, "Groceries copy", "newline/tab-only input is blank too")
    }

    func testDuplicatePersistsAcrossReload() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")
        store.addItem(to: source.id)
        guard let item = store.checklist(id: source.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        store.updateItem(checklistID: source.id, itemID: item.id, title: "Milk")
        let copied = store.duplicate(id: source.id, name: ChecklistStore.duplicateName(basedOn: "Groceries"))

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 2)
        let reloadedCopy = reloaded.checklist(id: copied?.id ?? UUID())
        XCTAssertEqual(reloadedCopy?.name, "Groceries copy")
        XCTAssertEqual(reloadedCopy?.items.map(\.title), ["Milk"])
        XCTAssertEqual(reloaded.checklist(id: source.id)?.items.map(\.title), ["Milk"])
    }

    func testDuplicateFiresOnChange() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        var changes = 0
        store.onChange = { changes += 1 }

        let source = store.create(name: "Groceries")
        XCTAssertEqual(changes, 1)

        store.duplicate(id: source.id, name: ChecklistStore.duplicateName(basedOn: "Groceries"))
        XCTAssertEqual(changes, 2, "a local duplicate notifies the sync coordinator")
    }

    func testDuplicateIgnoresAnUnknownID() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        var changes = 0
        store.onChange = { changes += 1 }

        XCTAssertNil(store.duplicate(id: UUID(), name: "x"))
        XCTAssertTrue(store.checklists.isEmpty)
        XCTAssertEqual(changes, 0, "an unknown id must not schedule a save")
    }

    func testSetDestinationUpdatesRevisionAndPersists() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        clock.now = Date(timeIntervalSince1970: 5)

        XCTAssertEqual(store.setDestination("list-a", for: created.id), .updated)

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.destinationListIdentifier, "list-a")
        XCTAssertEqual(reloaded.checklist(id: created.id)?.revision, 2)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.modifiedAt, clock.now)
    }

    func testSetDestinationClearsToDefaultWithNil() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.setDestination("list-a", for: created.id)

        XCTAssertEqual(store.setDestination(nil, for: created.id), .updated)

        XCTAssertNil(makeStore(defaults: suite.defaults).checklist(id: created.id)?.destinationListIdentifier)
    }

    /// Sad path: an id deleted while its edit screen was on the stack changes
    /// nothing and reports not-found.
    func testSetDestinationForUnknownChecklistReturnsNotFound() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let store = makeStore(defaults: suite.defaults)

        XCTAssertEqual(store.setDestination("list-a", for: UUID()), .notFound)
        XCTAssertTrue(store.checklists.isEmpty)
    }
}

