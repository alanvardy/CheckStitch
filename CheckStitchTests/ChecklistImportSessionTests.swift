@testable import CheckStitch
import CheckStitchCore
import Foundation
import Testing

@MainActor
struct ChecklistImportSessionTests {
    private func makeSession() -> (ChecklistImportSession, ChecklistStore) {
        let store = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        return (ChecklistImportSession(store: store), store)
    }

    private func payload(_ checklists: [Checklist], version: Int = ChecklistCodec.currentVersion) throws -> Data {
        try ChecklistCodec.encode(ChecklistEnvelope(version: version, deviceID: "", checklists: checklists))
    }

    @Test
    func prepareInsertsNonConflictingCandidates() throws {
        let (session, store) = makeSession()
        let candidates = try session.prepare(data: payload([
            Checklist(name: "A"),
            Checklist(name: "B"),
        ]))

        #expect(candidates.count == 2, "one candidate per incoming checklist")
        #expect(store.checklists.map(\.name) == ["A", "B"], "free names insert immediately")
        #expect(session.summary.inserted == 2)
        #expect(session.pending.isEmpty, "no conflicts left pending")
    }

    @Test
    func prepareFlagsConflictAndLeavesItUninserted() throws {
        let (session, store) = makeSession()
        store.create(name: "Groceries")

        let candidates = try session.prepare(data: payload([
            Checklist(name: "groceries", items: [ChecklistItem(title: "Milk")]),
        ]))

        #expect(candidates.count == 1)
        #expect(session.pending.count == 1, "conflicted name stays pending")
        #expect(session.pending.first?.conflicting?.name == "Groceries")
        #expect(store.checklists.count == 1, "conflicted import left the store untouched")
        #expect(session.summary.inserted == 0)
    }

    @Test
    func unsupportedVersionThrowsAndMutatesNothing() throws {
        let (session, store) = makeSession()
        let id = store.create(name: "Local").id
        let data = try payload([Checklist(name: "A")], version: ChecklistCodec.currentVersion + 1)

        #expect(throws: ChecklistImportError.unsupportedVersion) {
            try session.prepare(data: data)
        }

        #expect(store.checklists.count == 1, "store untouched by a future-version payload")
        #expect(store.checklists.first?.id == id)
        #expect(store.tombstones.isEmpty)
        #expect(session.pending.isEmpty)
    }

    @Test
    func unreadableThrowsAndMutatesNothing() {
        let (session, store) = makeSession()
        let id = store.create(name: "Local").id

        #expect(throws: ChecklistImportError.unreadable) {
            try session.prepare(data: Data("not json".utf8))
        }

        #expect(store.checklists.count == 1, "store untouched by an unreadable payload")
        #expect(store.checklists.first?.id == id)
        #expect(store.tombstones.isEmpty)
        #expect(session.pending.isEmpty)
    }

    @Test
    func migratablePayloadIsAccepted() throws {
        let (session, store) = makeSession()

        _ = try session.prepare(data: payload([Checklist(name: "V1")], version: 1))
        #expect(store.checklists.map(\.name) == ["V1"], "v1 payload migrates and inserts")
        #expect(session.summary.inserted == 1)
        #expect(session.pending.isEmpty)

        // The summary resets per file, so a second `prepare` starts from zero.
        _ = try session.prepare(data: payload([Checklist(name: "V2")], version: 2))
        #expect(store.checklists.map(\.name) == ["V1", "V2"], "v2 payload seeds ordering and inserts")
        #expect(session.summary.inserted == 1)
        #expect(session.pending.isEmpty)
    }

    @Test
    func replaceTombstonesAndSwaps() throws {
        let (session, store) = makeSession()
        let local = store.create(name: "Groceries")
        let incoming = Checklist(name: "Groceries", items: [
            ChecklistItem(title: "Milk", description: "2%", relativeDate: 1),
        ], modifiedAt: Date(timeIntervalSince1970: 100), revision: 7)

        try session.prepare(data: payload([incoming]))
        #expect(session.pending.count == 1)
        let candidateID = session.pending.first?.id ?? UUID()
        session.decide(.replace, for: candidateID)

        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.id != local.id, "replacement gets a fresh identity")
        #expect(store.checklists.first?.name == "Groceries")
        #expect(store.checklists.first?.revision == 1, "imported content never carries the source revision")
        #expect(store.tombstones.count == 1)
        #expect(store.tombstones.first?.checklistID == local.id)
        #expect(store.tombstones.first?.itemID == nil, "whole-checklist tombstone, like delete")
        #expect(store.tombstones.first?.revision == 2)
        #expect(session.summary.replaced == 1)
        #expect(session.pending.isEmpty)
    }

    @Test
    func keepBothDisambiguates() throws {
        let (session, store) = makeSession()
        store.create(name: "Groceries")

        try session.prepare(data: payload([
            Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")]),
        ]))
        #expect(session.pending.count == 1)
        session.decide(.keepBoth, for: session.pending.first?.id ?? UUID())

        #expect(store.checklists.map(\.name) == ["Groceries", "Groceries 2"], "uniqueName disambiguates the kept copy")
        #expect(session.summary.keptBoth == 1)
        #expect(session.pending.isEmpty)
    }

    @Test
    func keepExistingLeavesLocalIntact() throws {
        let (session, store) = makeSession()
        store.create(name: "Groceries")

        try session.prepare(data: payload([Checklist(name: "groceries")]))
        session.decide(.keepExisting, for: session.pending.first?.id ?? UUID())

        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.name == "Groceries")
        #expect(store.tombstones.isEmpty)
        #expect(session.summary.keptExisting == 1)
        #expect(session.pending.isEmpty)
    }

    @Test
    func importingSameFileTwiceIsStable() throws {
        let (session, store) = makeSession()
        let data = try payload([Checklist(name: "A")])

        let first = try session.prepare(data: data)
        #expect(first.count == 1)
        #expect(store.checklists.map(\.name) == ["A"])
        #expect(session.summary.inserted == 1)
        #expect(session.pending.isEmpty)

        // The same bytes again now collide with the stored copy.
        let second = try session.prepare(data: data)
        #expect(second.count == 1)
        #expect(session.pending.count == 1, "second import presents a conflict")
        #expect(session.summary.inserted == 0, "summary resets per file")
        session.decide(.keepExisting, for: session.pending.first?.id ?? UUID())

        #expect(store.checklists.count == 1)
        #expect(store.checklists.map(\.name) == ["A"])
    }

    /// A payload whose item is `.medium` imports with that priority intact —
    /// through the plain insert path and through a Replace decision. Rebuilds on
    /// both go through the store's `freshCopy`, which is the drop this test
    /// would have caught (priority resetting to `.none`).
    @Test
    func importPreservesPriority() throws {
        let incoming = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", priority: .medium)])

        // Insert path: a free name lands immediately.
        let (session, store) = makeSession()
        try session.prepare(data: payload([incoming]))
        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.items.first?.priority == .medium, "insert keeps the payload priority")
        #expect(store.checklists.first?.items.first?.priorityRevision == store.checklists.first?.items.first?.revision)

        // Replace path: the same name now conflicts, and replacing rebuilds the
        // checklist from the same payload.
        let (replacing, replaceStore) = makeSession()
        replaceStore.create(name: "Groceries")
        try replacing.prepare(data: payload([incoming]))
        #expect(replacing.pending.count == 1)
        replacing.decide(.replace, for: replacing.pending.first?.id ?? UUID())
        #expect(replaceStore.checklists.count == 1)
        #expect(replaceStore.checklists.first?.items.first?.priority == .medium, "replace keeps the payload priority")
        #expect(replaceStore.checklists.first?.items.first?.priorityRevision == replaceStore.checklists.first?.items.first?.revision)
    }
}
