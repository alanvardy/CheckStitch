import XCTest
@testable import CheckStitch

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
        let first = store.create()
        let second = store.create()
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
        store.create()
        store.create()

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
}
