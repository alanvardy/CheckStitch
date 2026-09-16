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

    /// Three named checklists — the smallest fixture that exercises batch removal.
    private func makeChecklistStore(defaults: UserDefaults, names: [String]) -> ChecklistStore {
        let store = makeStore(defaults: defaults)
        for name in names { _ = store.create(name: name) }
        return store
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
        // Field clocks seed from the upgraded coarse clock, so legacy items keep
        // today's whole-item semantics on every axis.
        XCTAssertEqual(store.checklists.first?.items.first?.titleRevision, 1)
        XCTAssertEqual(store.checklists.first?.items.first?.descriptionRevision, 1)
        XCTAssertEqual(store.checklists.first?.items.first?.relativeDateRevision, 1)
        XCTAssertEqual(store.checklists.first?.items.first?.titleModifiedAt, store.checklists.first?.items.first?.modifiedAt)
        XCTAssertEqual(store.checklists.first?.items.first?.descriptionModifiedAt, store.checklists.first?.items.first?.modifiedAt)
        XCTAssertEqual(store.checklists.first?.items.first?.relativeDateModifiedAt, store.checklists.first?.items.first?.modifiedAt)
        XCTAssertEqual(store.checklists.first?.items.first?.priority, ChecklistItemPriority.none)
        XCTAssertEqual(store.checklists.first?.items.first?.priorityRevision, 1)
        XCTAssertEqual(store.checklists.first?.items.first?.priorityModifiedAt, store.checklists.first?.items.first?.modifiedAt)
        // Ordering is seeded from the record's own sync state, granting no win.
        XCTAssertEqual(store.checklists.first?.orderRevision, 1)
        XCTAssertEqual(store.checklists.first?.itemOrder, store.checklists.first?.items.map(\.id))

        // The migrated payload is savable, not stalled in memory.
        store.create()

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 2)
        XCTAssertEqual(reloaded.checklists.first?.name, "Groceries")
    }

    /// A v1 payload (no priority keys, no sync state) and a current-version
    /// payload (priority keys written by the live encoder) for the same
    /// revision-1 item must agree on priority: `.none` with the priority clock
    /// seeded to the coarse revision on both paths.
    func testV1AndV4MigrationAgreeOnPriority() throws {
        let v1Suite = makeDefaults()
        defer { v1Suite.defaults.removePersistentDomain(forName: v1Suite.suiteName) }
        v1Suite.defaults.set(
            Data(#"{"version":1,"checklists":[{"id":"\#(UUID().uuidString)","name":"Groceries","items":[{"id":"\#(UUID().uuidString)","title":"Milk"}]}]}"#.utf8),
            forKey: key)
        let migrated = makeStore(defaults: v1Suite.defaults)
        guard let v1Item = migrated.checklists.first?.items.first else {
            XCTFail("expected the migrated v1 item")
            return
        }

        let v4 = try ChecklistCodec.encode(ChecklistEnvelope(
            version: ChecklistCodec.currentVersion,
            deviceID: "",
            checklists: [Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", revision: 1)])]))
        guard case .loaded(let env) = ChecklistCodec.classify(v4) else {
            XCTFail("expected the v4 payload to classify as loaded")
            return
        }
        guard let v4Item = env.checklists.first?.items.first else {
            XCTFail("expected the decoded v4 item")
            return
        }

        XCTAssertEqual(v1Item.priority, ChecklistItemPriority.none)
        XCTAssertEqual(v1Item.priorityRevision, v1Item.revision)
        XCTAssertEqual(v4Item.priority, ChecklistItemPriority.none)
        XCTAssertEqual(v4Item.priorityRevision, v4Item.revision)
    }

    func testDeviceIDIsStableAcrossInstances() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let first = makeStore(defaults: suite.defaults)
        let second = makeStore(defaults: suite.defaults)
        XCTAssertEqual(first.deviceID, second.deviceID)
        XCTAssertFalse(first.deviceID.isEmpty)
    }

    func testNewPayloadIsCurrentVersion() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        store.create()

        let data = try? XCTUnwrap(suite.defaults.data(forKey: key))
        guard case .loaded(let stored) = ChecklistCodec.classify(data ?? Data()) else {
            XCTFail("expected the stored payload to classify as loaded")
            return
        }
        XCTAssertEqual(stored.version, 4)
    }

    /// A stored v2 payload has real sync state but no ordering state. It must
    /// load with its revision, timestamp and tombstones intact, never be
    /// restamped, and have its ordering seeded from its own sync state. Built as
    /// raw JSON (not the current encoder) because a real v2 payload has no
    /// `itemOrder`/`orderRevision`/`orderModifiedAt` keys — a shape the current
    /// encoder can never produce under `version: 2`.
    func testV2PayloadLoadsWithoutRestampingAndSeedsOrdering() throws {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let checklistID = UUID()
        let itemID = UUID()
        let modifiedAt = Date(timeIntervalSinceReferenceDate: 1_234)
        let raw = Data(#"{"version":2,"deviceID":"remote-device","tombstones":[{"checklistID":"\#(checklistID)","deletedAt":1234,"revision":2}],"checklists":[{"id":"\#(checklistID)","name":"Groceries","modifiedAt":1234,"revision":9,"items":[{"id":"\#(itemID)","title":"Milk","modifiedAt":1234,"revision":7}]}]}"#.utf8)
        suite.defaults.set(raw, forKey: key)

        let store = makeStore(defaults: suite.defaults)
        XCTAssertTrue(store.canAcceptRemoteChanges, "a migrated v2 payload stays writable")
        XCTAssertEqual(store.checklists.first?.revision, 9, "v2 revisions must not be restamped")
        XCTAssertEqual(store.checklists.first?.modifiedAt, modifiedAt)
        XCTAssertEqual(store.checklists.first?.items.first?.revision, 7)
        XCTAssertEqual(store.checklists.first?.items.first?.modifiedAt, modifiedAt)
        XCTAssertEqual(store.checklists.first?.itemOrder, [itemID])
        XCTAssertEqual(store.checklists.first?.orderRevision, 9, "ordering is seeded from the record's own revision")
        XCTAssertEqual(store.checklists.first?.orderModifiedAt, modifiedAt)
        XCTAssertEqual(store.tombstones.count, 1, "v2 tombstones must survive migration")

        // Persist and reload: still not restamped, ordering still seeded.
        store.create()
        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.first(where: { $0.name == "Groceries" })?.revision, 9)
        XCTAssertEqual(reloaded.checklists.first(where: { $0.name == "Groceries" })?.orderRevision, 9)
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

    func testTitleEditStampsTitleClockAndLeavesDescriptionClock() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }

        clock.now = Date(timeIntervalSince1970: 20)
        store.updateItem(checklistID: created.id, itemID: item.id, title: "Milk")

        let edited = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(edited?.revision, 2)
        XCTAssertEqual(edited?.titleRevision, edited?.revision, "the title clock stamps the coarse revision")
        XCTAssertEqual(edited?.titleModifiedAt, clock.now)
        XCTAssertEqual(edited?.descriptionRevision, 1, "the description clock keeps the add-time stamp")
        XCTAssertEqual(edited?.descriptionModifiedAt, Date(timeIntervalSince1970: 10))
    }

    func testDescriptionEditStampsDescriptionClockAndLeavesTitleClock() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }

        clock.now = Date(timeIntervalSince1970: 20)
        store.updateItemDescription(checklistID: created.id, itemID: item.id, description: "2 litres")

        let edited = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(edited?.revision, 2)
        XCTAssertEqual(edited?.descriptionRevision, edited?.revision, "the description clock stamps the coarse revision")
        XCTAssertEqual(edited?.descriptionModifiedAt, clock.now)
        XCTAssertEqual(edited?.titleRevision, 1, "the title clock keeps the add-time stamp")
        XCTAssertEqual(edited?.titleModifiedAt, Date(timeIntervalSince1970: 10))
    }

    func testCreateAddAndDuplicateSeedEveryFieldClock() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        let added = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(added?.revision, 1)
        XCTAssertEqual(added?.modifiedAt, clock.now)
        XCTAssertEqual(added?.titleRevision, added?.revision)
        XCTAssertEqual(added?.titleModifiedAt, clock.now)
        XCTAssertEqual(added?.descriptionRevision, added?.revision)
        XCTAssertEqual(added?.descriptionModifiedAt, clock.now)

        clock.now = Date(timeIntervalSince1970: 50)
        let copy = store.duplicate(id: created.id, name: "Groceries copy")
        let duplicated = try? XCTUnwrap(copy?.items.first)
        XCTAssertEqual(duplicated?.revision, 1)
        XCTAssertEqual(duplicated?.modifiedAt, clock.now)
        XCTAssertEqual(duplicated?.titleRevision, 1, "a fresh duplicate seeds every field clock from its own now()/1")
        XCTAssertEqual(duplicated?.titleModifiedAt, clock.now)
        XCTAssertEqual(duplicated?.descriptionRevision, 1)
        XCTAssertEqual(duplicated?.descriptionModifiedAt, clock.now)
    }

    /// A title passed through the new create lands on the item without a second
    /// revision/clock bump: the add-item alert performs this single create with
    /// the typed name.
    func testAddItemWithTitleCreatesOnceUnderThatTitle() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id, title: "Milk")

        let added = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(added?.title, "Milk")
        XCTAssertEqual(added?.revision, 1)
        XCTAssertEqual(added?.modifiedAt, clock.now)
        XCTAssertEqual(added?.titleRevision, added?.revision, "the typed title is the add-time title, so its clock is untouched")
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

    func testUpdateItemRelativeDatePersists() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }

        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 3)

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.items.first?.relativeDate, 3)
    }

    func testUpdateItemRelativeDateClearsToNil() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else { return }
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 3)

        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: nil)

        XCTAssertNil(store.checklist(id: created.id)?.items.first?.relativeDate)
    }

    func testUpdateItemRelativeDateNoOpsWhenUnchanged() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else { return }
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)
        let revision = store.checklist(id: created.id)?.items.first?.revision

        var changes = 0
        store.onChange = { changes += 1 }
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)

        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.revision, revision)
        XCTAssertEqual(changes, 0, "an unchanged value must not schedule a save or push")
    }

    /// Re-committing an unchanged relative date must not bump any clock — not
    /// the coarse clock and none of the six field clocks — so it can never win a
    /// spurious LWW round (the per-axis extension of the no-op guard above).
    func testUnchangedRelativeDateIsANoOpForEveryClock() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        clock.now = Date(timeIntervalSince1970: 20)
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)
        guard let before = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the edited item")
            return
        }

        clock.now = Date(timeIntervalSince1970: 30)
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)

        let after = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(after?.revision, before.revision)
        XCTAssertEqual(after?.modifiedAt, before.modifiedAt)
        XCTAssertEqual(after?.relativeDate, before.relativeDate)
        XCTAssertEqual(after?.titleRevision, before.titleRevision)
        XCTAssertEqual(after?.titleModifiedAt, before.titleModifiedAt)
        XCTAssertEqual(after?.descriptionRevision, before.descriptionRevision)
        XCTAssertEqual(after?.descriptionModifiedAt, before.descriptionModifiedAt)
        XCTAssertEqual(after?.relativeDateRevision, before.relativeDateRevision)
        XCTAssertEqual(after?.relativeDateModifiedAt, before.relativeDateModifiedAt)
    }

    /// A changed relative date stamps only its own clock (and the coarse clock
    /// it rides on); the title and description clocks keep their own stamps.
    func testChangedRelativeDateStampsRelativeDateClockOnly() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        clock.now = Date(timeIntervalSince1970: 20)
        store.updateItem(checklistID: created.id, itemID: item.id, title: "Milk")
        clock.now = Date(timeIntervalSince1970: 30)
        store.updateItemDescription(checklistID: created.id, itemID: item.id, description: "2 litres")
        let titleRevision = store.checklist(id: created.id)?.items.first?.titleRevision
        let titleModifiedAt = store.checklist(id: created.id)?.items.first?.titleModifiedAt
        let descriptionRevision = store.checklist(id: created.id)?.items.first?.descriptionRevision
        let descriptionModifiedAt = store.checklist(id: created.id)?.items.first?.descriptionModifiedAt

        clock.now = Date(timeIntervalSince1970: 40)
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)

        let edited = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(edited?.revision, 4, "1 add + title + description + relative-date edit")
        XCTAssertEqual(edited?.relativeDateRevision, edited?.revision, "the relative-date clock stamps the coarse revision")
        XCTAssertEqual(edited?.relativeDateModifiedAt, clock.now)
        XCTAssertEqual(edited?.titleRevision, titleRevision, "the title clock keeps its own stamp")
        XCTAssertEqual(edited?.titleModifiedAt, titleModifiedAt)
        XCTAssertEqual(edited?.descriptionRevision, descriptionRevision, "the description clock keeps its own stamp")
        XCTAssertEqual(edited?.descriptionModifiedAt, descriptionModifiedAt)
    }

    func testUpdateItemRelativeDateIgnoresUnknownIDs() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        var changes = 0
        store.onChange = { changes += 1 }

        store.updateItem(checklistID: UUID(), itemID: UUID(), relativeDate: 1)
        store.updateItem(checklistID: created.id, itemID: UUID(), relativeDate: 1)

        XCTAssertEqual(changes, 0)
    }

    func testRelativeDateEditsAreCoalescedUntilFlush() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: .milliseconds(50))
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else { return }

        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 1)
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)

        XCTAssertEqual(store.checklist(id: created.id)?.items.first?.relativeDate, 2)
        XCTAssertNil(makeStore(defaults: suite.defaults).checklist(id: created.id)?.items.first?.relativeDate)

        store.flushPendingSave()
        XCTAssertEqual(makeStore(defaults: suite.defaults).checklist(id: created.id)?.items.first?.relativeDate, 2)
    }

    func testDuplicateCopiesRelativeDate() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")
        store.addItem(to: source.id)
        guard let item = store.checklist(id: source.id)?.items.first else { return }
        store.updateItem(checklistID: source.id, itemID: item.id, relativeDate: 2)
        store.updateItem(checklistID: source.id, itemID: item.id, priority: .high)

        let copy = store.duplicate(id: source.id, name: "Groceries copy")

        XCTAssertEqual(copy?.items.first?.relativeDate, 2)
        // The priority pick rides along on the fresh copy's re-seeded clock.
        XCTAssertEqual(copy?.items.first?.priority, ChecklistItemPriority.high)
        XCTAssertEqual(copy?.items.first?.priorityRevision, 1)
    }

    // MARK: - Priority

    /// A changed priority stamps only its own clock (and the coarse clock it
    /// rides on); the title/description/relative-date clocks keep their stamps.
    func testUpdateItemPriorityStampsBothClocks() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        clock.now = Date(timeIntervalSince1970: 20)
        store.updateItem(checklistID: created.id, itemID: item.id, title: "Milk")
        clock.now = Date(timeIntervalSince1970: 30)
        store.updateItemDescription(checklistID: created.id, itemID: item.id, description: "2 litres")
        clock.now = Date(timeIntervalSince1970: 40)
        store.updateItem(checklistID: created.id, itemID: item.id, relativeDate: 2)
        let titleRevision = store.checklist(id: created.id)?.items.first?.titleRevision
        let titleModifiedAt = store.checklist(id: created.id)?.items.first?.titleModifiedAt
        let descriptionRevision = store.checklist(id: created.id)?.items.first?.descriptionRevision
        let descriptionModifiedAt = store.checklist(id: created.id)?.items.first?.descriptionModifiedAt
        let relativeDateRevision = store.checklist(id: created.id)?.items.first?.relativeDateRevision
        let relativeDateModifiedAt = store.checklist(id: created.id)?.items.first?.relativeDateModifiedAt

        clock.now = Date(timeIntervalSince1970: 50)
        store.updateItem(checklistID: created.id, itemID: item.id, priority: .high)

        let edited = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(edited?.priority, ChecklistItemPriority.high)
        XCTAssertEqual(edited?.revision, 5, "1 add + title + description + relative-date + priority edits")
        XCTAssertEqual(edited?.priorityRevision, edited?.revision, "the priority clock stamps the coarse revision")
        XCTAssertEqual(edited?.priorityModifiedAt, clock.now)
        XCTAssertEqual(edited?.titleRevision, titleRevision, "the title clock keeps its own stamp")
        XCTAssertEqual(edited?.titleModifiedAt, titleModifiedAt)
        XCTAssertEqual(edited?.descriptionRevision, descriptionRevision, "the description clock keeps its own stamp")
        XCTAssertEqual(edited?.descriptionModifiedAt, descriptionModifiedAt)
        XCTAssertEqual(edited?.relativeDateRevision, relativeDateRevision, "the relative-date clock keeps its own stamp")
        XCTAssertEqual(edited?.relativeDateModifiedAt, relativeDateModifiedAt)
    }

    /// Re-committing an unchanged priority must not bump any clock — not the
    /// coarse clock and none of the field clocks — so it can never win a
    /// spurious LWW round (the discrete-pick no-op guard).
    func testUpdateItemPriorityNoOpsWhenUnchanged() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        clock.now = Date(timeIntervalSince1970: 20)
        store.updateItem(checklistID: created.id, itemID: item.id, priority: .high)
        guard let before = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the edited item")
            return
        }

        clock.now = Date(timeIntervalSince1970: 30)
        store.updateItem(checklistID: created.id, itemID: item.id, priority: .high)

        let after = try? XCTUnwrap(store.checklist(id: created.id)?.items.first)
        XCTAssertEqual(after?.revision, before.revision)
        XCTAssertEqual(after?.modifiedAt, before.modifiedAt)
        XCTAssertEqual(after?.priority, before.priority)
        XCTAssertEqual(after?.priorityRevision, before.priorityRevision)
        XCTAssertEqual(after?.priorityModifiedAt, before.priorityModifiedAt)
        XCTAssertEqual(after?.titleRevision, before.titleRevision)
        XCTAssertEqual(after?.titleModifiedAt, before.titleModifiedAt)
        XCTAssertEqual(after?.descriptionRevision, before.descriptionRevision)
        XCTAssertEqual(after?.descriptionModifiedAt, before.descriptionModifiedAt)
        XCTAssertEqual(after?.relativeDateRevision, before.relativeDateRevision)
        XCTAssertEqual(after?.relativeDateModifiedAt, before.relativeDateModifiedAt)
    }

    func testUpdateItemPriorityPersistsAndReloads() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }

        store.updateItem(checklistID: created.id, itemID: item.id, priority: .medium)

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklist(id: created.id)?.items.first?.priority, ChecklistItemPriority.medium)
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

    /// A reorder is a structural edit: it stamps only the ordering state, so
    /// every field clock (and the coarse item clock) survives untouched.
    func testMoveItemsLeavesEveryFieldClockUntouched() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }
        let clock = Clock()
        clock.now = Date(timeIntervalSince1970: 10)
        let store = ChecklistStore(defaults: suite.defaults, key: key, textEditDelay: nil, now: { clock.now })
        let checklistID = store.create(name: "Groceries").id
        store.addItem(to: checklistID)
        store.addItem(to: checklistID)
        guard let item = store.checklist(id: checklistID)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        clock.now = Date(timeIntervalSince1970: 20)
        store.updateItem(checklistID: checklistID, itemID: item.id, title: "A")
        clock.now = Date(timeIntervalSince1970: 30)
        store.updateItemDescription(checklistID: checklistID, itemID: item.id, description: "note")
        clock.now = Date(timeIntervalSince1970: 40)
        store.updateItem(checklistID: checklistID, itemID: item.id, relativeDate: 2)
        guard let before = store.checklist(id: checklistID)?.items.first else {
            XCTFail("expected the edited item")
            return
        }

        clock.now = Date(timeIntervalSince1970: 5_000)
        store.moveItems(checklistID: checklistID, from: IndexSet(integer: 0), to: 1)

        guard let after = store.checklist(id: checklistID)?.items.first else {
            XCTFail("expected the moved item")
            return
        }
        XCTAssertEqual(after.id, before.id, "a move preserves the item, only the order changes")
        XCTAssertEqual(after.title, before.title)
        XCTAssertEqual(after.description, before.description)
        XCTAssertEqual(after.relativeDate, before.relativeDate)
        XCTAssertEqual(after.revision, before.revision)
        XCTAssertEqual(after.modifiedAt, before.modifiedAt)
        XCTAssertEqual(after.titleRevision, before.titleRevision)
        XCTAssertEqual(after.titleModifiedAt, before.titleModifiedAt)
        XCTAssertEqual(after.descriptionRevision, before.descriptionRevision)
        XCTAssertEqual(after.descriptionModifiedAt, before.descriptionModifiedAt)
        XCTAssertEqual(after.relativeDateRevision, before.relativeDateRevision)
        XCTAssertEqual(after.relativeDateModifiedAt, before.relativeDateModifiedAt)
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

    // MARK: - removeChecklists

    func testRemoveChecklistsDeletesRowsAndLeavesTombstones() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        let groceries = store.checklists.first { $0.name == "Groceries" }
        let travel = store.checklists.first { $0.name == "Travel" }

        store.removeChecklists(at: IndexSet([0, 2]))

        XCTAssertEqual(store.checklists.map(\.name), ["Hardware"])
        XCTAssertEqual(store.tombstones.count, 2)
        XCTAssertTrue(store.tombstones.allSatisfy { $0.itemID == nil })
        let byID = Dictionary(uniqueKeysWithValues: store.tombstones.map { ($0.checklistID, $0) })
        XCTAssertEqual(byID[groceries?.id ?? UUID()]?.revision, (groceries?.revision ?? 0) + 1)
        XCTAssertEqual(byID[travel?.id ?? UUID()]?.revision, (travel?.revision ?? 0) + 1)
        XCTAssertTrue(store.tombstones.allSatisfy { $0.deletedAt.timeIntervalSince1970 > 0 })
    }

    /// Removing a checklist with items must produce exactly one whole-checklist
    /// tombstone (`itemID == nil`), never one per item.
    func testRemoveChecklistsLeavesOnlyWholeChecklistTombstones() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create(name: "Groceries")
        store.addItem(to: created.id)
        store.addItem(to: created.id)

        store.removeChecklists(at: IndexSet(integer: 0))

        XCTAssertTrue(store.checklists.isEmpty)
        XCTAssertEqual(store.tombstones.count, 1)
        XCTAssertEqual(store.tombstones.first?.checklistID, created.id)
        XCTAssertNil(store.tombstones.first?.itemID)
        XCTAssertEqual(store.tombstones.first?.revision, 2)
    }

    func testRemoveChecklistsOutOfRangeIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        let before = try? XCTUnwrap(suite.defaults.data(forKey: key))

        store.removeChecklists(at: IndexSet(integer: 7))

        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Hardware", "Travel"])
        XCTAssertTrue(store.tombstones.isEmpty)
        XCTAssertEqual(suite.defaults.data(forKey: key), before)
    }

    func testRemoveChecklistsEmptyOffsetsIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        var changes = 0
        store.onChange = { changes += 1 }

        store.removeChecklists(at: IndexSet())

        XCTAssertEqual(store.checklists.count, 3)
        XCTAssertEqual(changes, 0, "an empty offset set must not schedule a save")
    }

    func testRemoveChecklistsSavesOnce() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel", "Chores"])
        var changes = 0
        store.onChange = { changes += 1 }

        store.removeChecklists(at: IndexSet([0, 3]))

        XCTAssertEqual(store.checklists.map(\.name), ["Hardware", "Travel"])
        XCTAssertEqual(changes, 1, "a multi-row removal is one save and one sync push")
    }

    func testRemoveChecklistsPersistsAcrossReload() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        store.removeChecklists(at: IndexSet([0, 2]))

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["Hardware"])
        XCTAssertEqual(reloaded.tombstones.count, 2)
    }

    // MARK: - moveChecklists

    func testMoveChecklistsReordersWithinList() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        store.moveChecklists(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(store.checklists.map(\.name), ["Hardware", "Groceries", "Travel"])
    }

    func testMoveChecklistsToEnd() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        store.moveChecklists(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(store.checklists.map(\.name), ["Hardware", "Travel", "Groceries"])
    }

    func testMoveChecklistsOutOfRangeIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        let before = try? XCTUnwrap(suite.defaults.data(forKey: key))

        store.moveChecklists(from: IndexSet(integer: 5), to: 0)
        store.moveChecklists(from: IndexSet(integer: 0), to: 99)

        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Hardware", "Travel"])
        XCTAssertEqual(suite.defaults.data(forKey: key), before)
    }

    func testMoveChecklistsEmptyOffsetsIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        var changes = 0
        store.onChange = { changes += 1 }

        store.moveChecklists(from: IndexSet(), to: 1)

        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Hardware", "Travel"])
        XCTAssertEqual(changes, 0, "an empty offset set must not schedule a save")
    }

    /// A reorder is never mistaken for a checklist edit: every checklist keeps
    /// its `id`, `name`, `revision`, `modifiedAt`, `items` and `itemOrder` —
    /// only the top-level array order changes, so a reorder must not win an
    /// LWW round against another device's edit.
    func testMoveChecklistsPreservesChecklistIdentity() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let groceries = store.create(name: "Groceries")
        store.addItem(to: groceries.id)
        store.updateItem(checklistID: groceries.id, itemID: store.checklist(id: groceries.id)?.items.first?.id ?? UUID(), title: "Apples")
        let hardware = store.create(name: "Hardware")
        let travel = store.create(name: "Travel")
        let beforeByID = Dictionary(uniqueKeysWithValues: store.checklists.map { ($0.id, $0) })

        store.moveChecklists(from: IndexSet(integer: 0), to: 3)

        XCTAssertEqual(store.checklists.map(\.name), ["Hardware", "Travel", "Groceries"])
        for checklist in store.checklists {
            let before = beforeByID[checklist.id]
            XCTAssertEqual(checklist.id, before?.id)
            XCTAssertEqual(checklist.name, before?.name)
            XCTAssertEqual(checklist.revision, before?.revision)
            XCTAssertEqual(checklist.modifiedAt, before?.modifiedAt)
            XCTAssertEqual(checklist.items, before?.items)
            XCTAssertEqual(checklist.itemOrder, before?.itemOrder)
        }
    }

    func testMoveChecklistsPersistsAcrossReload() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeChecklistStore(defaults: suite.defaults, names: ["Groceries", "Hardware", "Travel"])
        store.moveChecklists(from: IndexSet(integer: 0), to: 2)

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.map(\.name), ["Hardware", "Groceries", "Travel"])
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

    /// Guards the tombstone invariant against the new clock fields: a removed
    /// item's tombstone still outlives any resurrected copy because its revision
    /// is exactly `removed.revision + 1`.
    func testTombstoneRevisionIsRemovedRevisionPlusOne() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let created = store.create()
        store.addItem(to: created.id)
        guard let item = store.checklist(id: created.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        store.updateItem(checklistID: created.id, itemID: item.id, title: "Milk")
        let removed = try? XCTUnwrap(store.checklist(id: created.id)?.items.first?.revision)

        store.removeItems(from: created.id, at: IndexSet(integer: 0))

        let tombstone = try? XCTUnwrap(store.tombstones.first)
        XCTAssertEqual(tombstone?.itemID, item.id)
        XCTAssertEqual(tombstone?.revision, (removed ?? 0) + 1)
        XCTAssertEqual(store.tombstones.count, 1)
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

    /// Duplicate and the import primitives (`freshCopy`) rebuild every item with
    /// fresh identity and fresh clocks; the priority value rides along on both
    /// paths — the "and import" half is what used to reset priority to `.none`.
    func testPrioritySurvivesDuplicateAndImport() throws {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = store.create(name: "Groceries")
        store.addItem(to: source.id)
        guard let item = store.checklist(id: source.id)?.items.first else {
            XCTFail("expected the added item")
            return
        }
        store.updateItem(checklistID: source.id, itemID: item.id, priority: .high)

        let copy = store.duplicate(id: source.id, name: "Groceries copy")
        XCTAssertEqual(copy?.items.first?.priority, ChecklistItemPriority.high)
        XCTAssertEqual(copy?.items.first?.priorityRevision, copy?.items.first?.revision)

        let incoming = Checklist(name: "Packing",
                                 items: [ChecklistItem(title: "Suitcase", priority: .medium)],
                                 modifiedAt: Date(timeIntervalSince1970: 100), revision: 7)
        let inserted = store.importInsert(incoming)
        guard let insertedItem = store.checklist(id: inserted)?.items.first else {
            XCTFail("expected the imported item")
            return
        }
        XCTAssertEqual(insertedItem.priority, ChecklistItemPriority.medium)
        XCTAssertEqual(insertedItem.priorityRevision, insertedItem.revision)
        XCTAssertEqual(insertedItem.revision, 1, "imported content never carries the source revision")

        let local = store.create(name: "Trip")
        guard let replaced = store.importReplace(id: local.id, with: incoming) else {
            XCTFail("expected the replace to land")
            return
        }
        guard let replacedItem = store.checklist(id: replaced)?.items.first else {
            XCTFail("expected the replaced item")
            return
        }
        XCTAssertEqual(replacedItem.priority, ChecklistItemPriority.medium)
        XCTAssertEqual(replacedItem.priorityRevision, replacedItem.revision)
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

    // MARK: - Import primitives

    /// An "imported" checklist with non-default identity, so freshness is provable.
    private func makeImportedChecklist(name: String = "Groceries",
                                       items: [String] = ["Milk", "Eggs"]) -> Checklist {
        Checklist(name: name,
                  items: items.map { ChecklistItem(title: $0, description: "\($0) notes", relativeDate: 1) },
                  modifiedAt: Date(timeIntervalSince1970: 100), revision: 7)
    }

    func testImportInsertGivesFreshIdentityAndPreservesName() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let source = makeImportedChecklist()
        let inserted = store.importInsert(source)

        let copy = try? XCTUnwrap(store.checklist(id: inserted))
        XCTAssertEqual(copy?.name, "Groceries")
        XCTAssertEqual(copy?.revision, 1, "imported revision is not carried over")
        XCTAssertNotEqual(copy?.id, source.id)
        XCTAssertEqual(copy?.items.count, 2)
        XCTAssertEqual(copy?.items.map(\.title), ["Milk", "Eggs"])
        XCTAssertEqual(copy?.items.map(\.description), ["Milk notes", "Eggs notes"])
        XCTAssertEqual(copy?.items.map(\.relativeDate), [1, 1])
        XCTAssertTrue(copy?.items.allSatisfy { predicted in
            source.items.allSatisfy { $0.id != predicted.id }
        } ?? false, "every item gets a fresh id")
        XCTAssertEqual(copy?.items.map(\.revision), [1, 1])
        XCTAssertTrue(store.tombstones.isEmpty)

        let reloaded = makeStore(defaults: suite.defaults)
        XCTAssertEqual(reloaded.checklists.count, 1)
        XCTAssertEqual(reloaded.checklists.first?.name, "Groceries")
    }

    func testImportInsertDisambiguatesNameAutomaticallyAndViaOverride() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let local = store.create(name: "Groceries")
        store.importInsert(makeImportedChecklist())
        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Groceries 2"])

        store.importInsert(makeImportedChecklist(), as: "Custom")
        XCTAssertEqual(store.checklists.map(\.name), ["Groceries", "Groceries 2", "Custom"])
        XCTAssertEqual(store.checklist(id: local.id)?.name, "Groceries")
    }

    func testImportInsertFiresOnChange() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        var changes = 0
        store.onChange = { changes += 1 }

        store.importInsert(makeImportedChecklist())
        XCTAssertEqual(changes, 1, "an import notifies the sync coordinator")
    }

    func testImportReplaceRemovesLocalAndRecordsWholeChecklistTombstone() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let local = store.create(name: "Groceries")
        let replacedID = try? XCTUnwrap(store.importReplace(id: local.id, with: makeImportedChecklist()))

        let copy = try? XCTUnwrap(store.checklist(id: replacedID ?? UUID()))
        XCTAssertEqual(store.checklists.count, 1, "a replace swaps, not duplicates")
        XCTAssertNotEqual(copy?.id, local.id)
        XCTAssertEqual(copy?.name, "Groceries")
        XCTAssertEqual(copy?.revision, 1)
        XCTAssertNil(store.checklist(id: local.id))

        XCTAssertEqual(store.tombstones.count, 1)
        XCTAssertEqual(store.tombstones.first?.checklistID, local.id)
        XCTAssertNil(store.tombstones.first?.itemID)
        XCTAssertEqual(store.tombstones.first?.revision, 2)
    }

    func testImportReplaceUnknownIdIsNoOp() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let local = store.create(name: "Groceries")
        XCTAssertNil(store.importReplace(id: UUID(), with: makeImportedChecklist()))
        XCTAssertEqual(store.checklists.count, 1)
        XCTAssertEqual(store.checklists.first?.id, local.id)
        XCTAssertTrue(store.tombstones.isEmpty)
    }

    func testConflictingChecklistMatchesTrimmedCaseInsensitiveName() {
        let suite = makeDefaults()
        defer { suite.defaults.removePersistentDomain(forName: suite.suiteName) }

        let store = makeStore(defaults: suite.defaults)
        let local = store.create(name: "Groceries")

        XCTAssertEqual(store.conflictingChecklist(named: "groceries")?.id, local.id)
        XCTAssertEqual(store.conflictingChecklist(named: " groceries ")?.id, local.id)
        XCTAssertEqual(store.conflictingChecklist(named: "GROCERIES")?.id, local.id)
        XCTAssertNil(store.conflictingChecklist(named: "Milk"))
    }
}

