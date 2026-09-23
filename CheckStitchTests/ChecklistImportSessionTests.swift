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

    private func allIDs(_ candidates: [ChecklistImportCandidate]) -> Set<UUID> {
        Set(candidates.map(\.id))
    }

    @Test
    func stagingWritesNothingToStore() throws {
        let (session, store) = makeSession()
        let candidates = try session.stage(data: payload([
            Checklist(name: "A"),
            Checklist(name: "B"),
        ]))

        #expect(store.checklists.isEmpty, "stage writes nothing to the store")
        #expect(store.tombstones.isEmpty)
        #expect(session.pending.isEmpty)
        #expect(session.summary == ImportSummary())
        #expect(candidates.count == 2, "one candidate per incoming checklist")
        #expect(candidates.first?.conflicting == nil)
    }

    @Test
    func commitImportsOnlySelected() throws {
        let (session, store) = makeSession()
        let candidates = try session.stage(data: payload([
            Checklist(name: "A"),
            Checklist(name: "B"),
        ]))

        session.commit(selectedIDs: allIDs([candidates[1]]))

        #expect(store.checklists.map(\.name) == ["B"], "only the selected checklist imports")
        #expect(session.summary.inserted == 1)
        #expect(session.pending.isEmpty)
    }

    @Test
    func commitSkipsUnselectedConflicts() throws {
        let (session, store) = makeSession()
        store.create(name: "Groceries")
        let candidates = try session.stage(data: payload([
            Checklist(name: "Groceries"),
            Checklist(name: "A"),
        ]))

        // Select only the free-name checklist; the unselected conflict is never
        // enqueued.
        session.commit(selectedIDs: allIDs([candidates[1]]))

        #expect(store.checklists.map(\.name) == ["Groceries", "A"], "unselected conflict is not imported")
        #expect(session.pending.isEmpty, "an unticked conflict is never enqueued")
        #expect(session.summary.inserted == 1)
    }

    @Test
    func commitEnqueuesSelectedConflictsInFileOrder() throws {
        let (session, store) = makeSession()
        store.create(name: "Groceries")
        _ = try session.stage(data: payload([
            Checklist(name: "Groceries"),
            Checklist(name: "A"),
            Checklist(name: "groceries"),
        ]))

        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(session.pending.map(\.checklist.name) == ["Groceries", "groceries"], "file order, second is the case-variant")
        #expect(session.summary.inserted == 1, "only A inserted")
    }

    @Test
    func discardLeavesStoreUnchanged() throws {
        let (session, store) = makeSession()
        _ = try session.stage(data: payload([Checklist(name: "A")]))

        session.discard()

        #expect(session.candidates.isEmpty)
        #expect(session.pending.isEmpty)
        #expect(store.checklists.isEmpty, "cancel touches nothing")
    }

    @Test
    func unsupportedVersionThrowsBeforeStaging() throws {
        let (session, store) = makeSession()
        let id = store.create(name: "Local").id
        let data = try payload([Checklist(name: "A")], version: ChecklistCodec.currentVersion + 1)

        #expect(throws: ChecklistImportError.unsupportedVersion) {
            try session.stage(data: data)
        }

        #expect(store.checklists.count == 1, "store untouched by a future-version payload")
        #expect(store.checklists.first?.id == id)
        #expect(store.tombstones.isEmpty)
        #expect(session.candidates.isEmpty)
    }

    @Test
    func unreadableThrowsBeforeStaging() {
        let (session, store) = makeSession()
        let id = store.create(name: "Local").id

        #expect(throws: ChecklistImportError.unreadable) {
            try session.stage(data: Data("not json".utf8))
        }

        #expect(store.checklists.count == 1, "store untouched by an unreadable payload")
        #expect(store.checklists.first?.id == id)
        #expect(store.tombstones.isEmpty)
        #expect(session.candidates.isEmpty)
    }

    @Test
    func migratableStagesNormalisedCandidates() throws {
        let (session, store) = makeSession()

        _ = try session.stage(data: payload([Checklist(name: "V1")], version: 1))
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(store.checklists.map(\.name) == ["V1"], "v1 payload migrates and commits")
        #expect(session.summary.inserted == 1)
        #expect(session.pending.isEmpty)

        // The summary/candidates reset per file, so a second stage starts from zero.
        _ = try session.stage(data: payload([Checklist(name: "V2")], version: 2))
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(store.checklists.map(\.name) == ["V1", "V2"], "v2 payload seeds ordering and commits")
        #expect(session.summary.inserted == 1)
        #expect(session.pending.isEmpty)
    }

    @Test
    func reImportStability() throws {
        let (session, store) = makeSession()
        let data = try payload([Checklist(name: "A")])

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(store.checklists.map(\.name) == ["A"])
        #expect(session.summary.inserted == 1)
        #expect(session.pending.isEmpty)

        // The same bytes again now collide with the stored copy.
        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(session.pending.count == 1, "second import presents a conflict")
        #expect(session.summary.inserted == 0, "summary resets per file")
        session.decide(.keepExisting, for: session.pending.first?.id ?? UUID())

        #expect(store.checklists.count == 1)
        #expect(store.checklists.map(\.name) == ["A"])
        #expect(store.tombstones.isEmpty)
    }

    /// A payload whose item is `.high` imports with that priority intact —
    /// through the plain insert path and through a Replace decision. Rebuilds on
    /// both go through the store's `freshCopy`, which is the drop this test
    /// would have caught (priority resetting to `.none`).
    @Test
    func priorityPreserved() throws {
        let incoming = Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk", priority: .high)])

        // Insert path: a free name lands on commit.
        let (session, store) = makeSession()
        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.items.first?.priority == .high, "insert keeps the payload priority")
        #expect(store.checklists.first?.items.first?.priorityRevision == store.checklists.first?.items.first?.revision)

        // Replace path: the same name now conflicts, and replacing rebuilds the
        // checklist from the same payload.
        let (replacing, replaceStore) = makeSession()
        replaceStore.create(name: "Groceries")
        _ = try replacing.stage(data: payload([incoming]))
        replacing.commit(selectedIDs: allIDs(replacing.candidates))
        #expect(replacing.pending.count == 1)
        replacing.decide(.replace, for: replacing.pending.first?.id ?? UUID())
        #expect(replaceStore.checklists.count == 1)
        #expect(replaceStore.checklists.first?.items.first?.priority == .high, "replace keeps the payload priority")
        #expect(replaceStore.checklists.first?.items.first?.priorityRevision == replaceStore.checklists.first?.items.first?.revision)
    }

    /// The imported destination survives the whole stage/commit path through the
    /// plain insert and through a Replace decision. Both rebuild via `freshCopy`.
    @Test
    func destinationPreserved() throws {
        let incoming = Checklist(name: "Groceries", destinationListIdentifier: "list-a")

        let (session, store) = makeSession()
        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(store.checklists.first?.destinationListIdentifier == "list-a",
                "insert keeps the payload destination")

        let (replacing, replaceStore) = makeSession()
        replaceStore.create(name: "Groceries")
        _ = try replacing.stage(data: payload([incoming]))
        replacing.commit(selectedIDs: allIDs(replacing.candidates))
        replacing.decide(.replace, for: replacing.pending.first?.id ?? UUID())
        #expect(replaceStore.checklists.first?.destinationListIdentifier == "list-a",
                "replace keeps the payload destination")
    }

    /// A source-device destination id is usually absent on the target. Import
    /// must keep it (a re-created list could match later) and the run-path net
    /// must fail closed before creating anything.
    @Test
    func staleImportedDestinationFailsClosedAtFirstRun() async throws {
        let (session, store) = makeSession()
        let incoming = Checklist(name: "Groceries",
                                 items: [ChecklistItem(title: "Milk")],
                                 destinationListIdentifier: "list-deleted")
        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))

        let imported = try #require(store.checklists.first)
        #expect(imported.destinationListIdentifier == "list-deleted",
                "the id is preserved, not silently reset")

        let spy = SpyReminderDestination()
        spy.lists = ReminderListsSnapshot(
            options: [ReminderListOption(id: "list-a", title: "Reminders")],
            defaultIdentifier: "list-a")

        let gate = RunGate(counter: RunCounter(defaults: makeIsolatedDefaults()),
                           isUnlocked: true)
        let outcome = await ChecklistReminders.create(from: imported, targeting: spy, gate: gate)

        #expect(outcome == .destinationMissing)
        #expect(spy.createdTitles.isEmpty, "no reminders created for a stale destination")
    }

    @Test
    func replaceTombstonesAndSwaps() throws {
        let (session, store) = makeSession()
        let local = store.create(name: "Groceries")
        let incoming = Checklist(name: "Groceries", items: [
            ChecklistItem(title: "Milk", description: "2%", relativeDate: 1),
        ], modifiedAt: Date(timeIntervalSince1970: 100), revision: 7)

        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))
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

        _ = try session.stage(data: payload([
            Checklist(name: "Groceries", items: [ChecklistItem(title: "Milk")]),
        ]))
        session.commit(selectedIDs: allIDs(session.candidates))
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

        _ = try session.stage(data: payload([Checklist(name: "groceries")]))
        session.commit(selectedIDs: allIDs(session.candidates))
        session.decide(.keepExisting, for: session.pending.first?.id ?? UUID())

        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.name == "Groceries")
        #expect(store.tombstones.isEmpty)
        #expect(session.summary.keptExisting == 1)
        #expect(session.pending.isEmpty)
    }
}
