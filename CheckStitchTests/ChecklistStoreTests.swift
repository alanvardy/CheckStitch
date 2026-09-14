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

    func testV2PayloadIsMigratedAndSavable() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        // A true v2 payload: version 2 with deviceID/tombstones and sync-stamped
        // records but no order keys — migration seeds the ordering state.
        let v2 = Data(#"{"version":2,"deviceID":"other-device","tombstones":[],"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","modifiedAt":1700000000,"revision":2,"items":[{"id":"\#(UUID().uuidString)","title":"Milk","modifiedAt":1700000000,"revision":2}]}]}"#.utf8)
        suite.defaults.set(v2, forKey: key)

        let store = makeStore(defaults: suite.defaults)
        let checklist = try? XCTUnwrap(store.checklists.first)
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertGreaterThanOrEqual(checklist?.orderRevision ?? 0, 1, "migration seeds ordering from the checklist's own revision")
        XCTAssertEqual(checklist?.itemOrder, checklist?.items.map(\.id))

        // The migrated payload is savable, not stalled in memory.
        store.create()

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 2)
        XCTAssertEqual(reloaded.checklists.first?.name, "Groceries")
        XCTAssertGreaterThanOrEqual(reloaded.checklists.first?.orderRevision ?? 0, 1)
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
}

