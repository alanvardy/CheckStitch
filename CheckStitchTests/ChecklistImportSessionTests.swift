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

    private func payload(_ checklists: [Checklist],
                     folders: [Folder] = [],
                     folderTombstones: [FolderTombstone] = [],
                     version: Int = ChecklistCodec.currentVersion) throws -> Data {
        try ChecklistCodec.encode(ChecklistEnvelope(version: version, deviceID: "",
                                                    checklists: checklists,
                                                    folders: folders,
                                                    folderTombstones: folderTombstones))
    }

    /// A payload whose single checklist belongs to a folder with `folderName`.
    /// The folder rides along by name (export carries referenced folders).
    private func payloadWithFolder(_ folderName: String, checklistName: String) throws -> Data {
        let source = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let folder = source.createFolder(name: folderName)
        let member = source.create(name: checklistName)
        source.moveChecklist(id: member.id, toFolder: folder.id)
        guard let memberWithFolder = source.checklist(id: member.id) else {
            fatalError("member checklist vanished")
        }
        return try ChecklistExport.data(checklists: [memberWithFolder], from: source.folders)
    }

    /// A payload whose single checklist carries a `folderID` that names no folder
    /// in the file (the folder was dropped from the export). Used to exercise an
    /// unresolved file-folder id.
    private func payloadWithOrphanFolderID(checklistName: String) throws -> Data {
        let source = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let folder = source.createFolder(name: "Unreferenced")
        let member = source.create(name: checklistName)
        source.moveChecklist(id: member.id, toFolder: folder.id)
        guard let memberWithFolder = source.checklist(id: member.id) else {
            fatalError("member checklist vanished")
        }
        return try ChecklistExport.data(checklists: [memberWithFolder], from: [])
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

    /// A hand-built out-of-range payload clamps into `multipleRange` during
    /// `stage`'s decode, so commit lands a valid factor.
    @Test
    func stagingClampsOutOfRangeMultiple() throws {
        let (session, store) = makeSession()
        _ = try session.stage(data: payload([Checklist(name: "A", multiple: 100)]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.multiple == 99, "100 clamps to 99 on stage")

        let (other, otherStore) = makeSession()
        _ = try other.stage(data: payload([Checklist(name: "B", multiple: 0)]))
        other.commit(selectedIDs: allIDs(other.candidates))
        #expect(otherStore.checklists.first?.multiple == 1, "0 clamps to 1 on stage")
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

    /// An archived source imports active on the plain insert path (Keep Both):
    /// `freshCopy` deliberately drops the archive state so imported content
    /// always lands visible, never hidden in the archived screen.
    @Test
    func importInsertLandsActive() throws {
        let (session, store) = makeSession()
        let incoming = Checklist(name: "Archived source", isArchived: true,
                                 archivedAt: Date(timeIntervalSince1970: 100))

        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.isArchived == false, "insert lands active")
        #expect(store.checklists.first?.archivedAt == nil, "insert clears the archive stamp")
    }

    /// An archived source imported through a Replace decision also lands active:
    /// the fallback to `freshCopy` must not preserve the source's archive state.
    @Test
    func importReplaceLandsActive() throws {
        let (session, store) = makeSession()
        store.create(name: "Groceries")
        let incoming = Checklist(name: "Groceries", isArchived: true,
                                 archivedAt: Date(timeIntervalSince1970: 100))

        _ = try session.stage(data: payload([incoming]))
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(session.pending.count == 1)
        session.decide(.replace, for: session.pending.first?.id ?? UUID())

        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.isArchived == false, "replace lands active")
        #expect(store.checklists.first?.archivedAt == nil, "replace clears the archive stamp")
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

    /// A source store with one folder and a member checklist; returns the export
    /// payload for just that member (the folder rides along).
    private func folderBearingPayload() throws -> Data {
        let source = ChecklistStore(defaults: makeIsolatedDefaults(), textEditDelay: nil)
        let folder = source.createFolder(name: "Groceries")
        let member = source.create(name: "Groceries")
        source.moveChecklist(id: member.id, toFolder: folder.id)
        guard let memberWithFolder = source.checklist(id: member.id) else {
            fatalError("member checklist vanished")
        }
        return try ChecklistExport.data(checklists: [memberWithFolder], from: source.folders)
    }

    /// A folder-bearing export into an empty store recreates the folder by name
    /// and reparents the imported checklist into it.
    @Test
    func exportedFolderIsRecreatedWhenImportingIntoEmptyStore() throws {
        let (session, store) = makeSession()
        let data = try folderBearingPayload()

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.folders.map(\.name) == ["Groceries"])
        let localFolder = try #require(store.folders.first)
        #expect(store.checklists.first?.folderID == localFolder.id)
    }

    /// Staging a folder-bearing file resolves nothing against the store: no
    /// folder and no checklist are written until commit.
    @Test
    func stagingAFolderBearingFileWritesNothing() throws {
        let (session, store) = makeSession()

        _ = try session.stage(data: try folderBearingPayload())

        #expect(store.folders.isEmpty)
        #expect(store.checklists.isEmpty)
    }

    /// Re-importing a folder-bearing file into the same store, resolving the
    /// resulting name conflict via Keep Both, must not mint a duplicate folder:
    /// the second commit's `folderMap` resolves to the existing "Groceries". (Phase
    /// 1 asserts folder non-duplication only; the Keep Both survivor's membership
    /// in that folder is Phase 2 scope — plan wording adjusted.)
    @Test
    func reImportingTheSameFileDoesNotDuplicateFolder() throws {
        let data = try folderBearingPayload()
        let (session, store) = makeSession()

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(store.folders.count == 1)

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(session.pending.count == 1, "the same-name checklist now conflicts")
        session.decide(.keepBoth, for: session.pending.first?.id ?? UUID())

        #expect(store.folders.count == 1, "a re-import never mints a duplicate folder")
        #expect(store.folders.map(\.name) == ["Groceries"])

        let folder = try #require(store.folders.first)
        let survivor = try #require(store.checklists.first { $0.name != "Groceries" })
        #expect(survivor.folderID == folder.id, "Keep Both survivor carries the folder membership")
    }

    /// Replacing a conflicting loose checklist re-parents the survivor into the
    /// folder the file's checklist belonged to (resolved by name).
    @Test
    func replaceReparentsTheSurvivorIntoTheImportedFolder() throws {
        let data = try payloadWithFolder("Work", checklistName: "Groceries")
        let (session, store) = makeSession()
        store.create(name: "Groceries")   // loose local conflict

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(session.pending.count == 1)
        session.decide(.replace, for: session.pending.first?.id ?? UUID())

        let workFolder = try #require(store.folders.first { $0.name == "Work" })
        #expect(store.checklists.count == 1, "replace removes the local original")
        #expect(store.checklists.first?.folderID == workFolder.id, "survivor is in the imported folder")
    }

    /// A file checklist whose `folderID` names no folder in the payload resolves
    /// to `nil`; the `.replace` survivor lands loose.
    @Test
    func replaceWithUnresolvedFileFolderLandsLoose() throws {
        let data = try payloadWithOrphanFolderID(checklistName: "Groceries")
        let (session, store) = makeSession()
        store.create(name: "Groceries")

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        #expect(session.pending.count == 1)
        session.decide(.replace, for: session.pending.first?.id ?? UUID())

        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.folderID == nil, "unresolved folder id lands the survivor loose")
        #expect(store.folders.isEmpty)
    }

    /// Keep Both imports a copy that joins the file's folder (resolved by name)
    /// while the local original keeps its own membership (none).
    @Test
    func keepBothCopyLandsInTheImportedFolder() throws {
        let data = try payloadWithFolder("Groceries", checklistName: "Groceries")
        let (session, store) = makeSession()
        let original = store.create(name: "Groceries")

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        session.decide(.keepBoth, for: session.pending.first?.id ?? UUID())

        let folder = try #require(store.folders.first)
        #expect(store.checklists.count == 2)
        let localOriginal = try #require(store.checklist(id: original.id))
        #expect(localOriginal.folderID == nil, "local original unchanged")
        let keptBoth = try #require(store.checklists.first { $0.name != "Groceries" })
        #expect(keptBoth.folderID == folder.id, "kept-both copy joins the imported folder")
    }

    /// Keep Existing writes nothing: no folder is minted for the file's folder
    /// and the local member keeps its membership.
    @Test
    func keepExistingLeavesLocalFoldersUntouched() throws {
        let data = try payloadWithFolder("Work", checklistName: "Groceries")
        let (session, store) = makeSession()
        let homeFolder = store.createFolder(name: "Home")
        let localMember = store.create(name: "Groceries")
        store.moveChecklist(id: localMember.id, toFolder: homeFolder.id)

        _ = try session.stage(data: data)
        session.commit(selectedIDs: allIDs(session.candidates))
        session.decide(.keepExisting, for: session.pending.first?.id ?? UUID())

        #expect(store.folders.map(\.name) == ["Home"], "keepExisting mints no folders")
        let localMemberNow = try #require(store.checklist(id: localMember.id))
        #expect(localMemberNow.folderID == homeFolder.id, "local member unchanged")
        #expect(session.summary.keptExisting == 1)
    }

    /// A file checklist whose `folderID` names no folder in the payload lands
    /// loose: the folder is never minted and nothing crashes.
    @Test
    func checklistWithOrphanFolderIDLandsLoose() throws {
        let (session, store) = makeSession()
        let orphanFile = Checklist(name: "Loose", folderID: UUID())

        _ = try session.stage(data: payload([orphanFile]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.folders.isEmpty)
        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.folderID == nil, "orphan folder id resolves loose")
    }

    /// A freshly minted folder adopts the file's collapse state.
    @Test
    func importedCollapseStateIsAdoptedOnFolderCreate() throws {
        let fileFolder = Folder(name: "Work", isCollapsed: true)
        let member = Checklist(name: "Meeting", folderID: fileFolder.id)
        let (session, store) = makeSession()

        _ = try session.stage(data: payload([member], folders: [fileFolder]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.folders.count == 1)
        #expect(store.folders.first?.name == "Work")
        #expect(store.folders.first?.isCollapsed == true, "file collapse state adopted on create")
    }

    /// Reusing an existing same-name folder keeps THAT folder's local collapse
    /// state; the file's isCollapsed is ignored for a reuse.
    @Test
    func existingFolderKeepsItsLocalCollapseState() throws {
        let fileFolder = Folder(name: "Work", isCollapsed: true)
        let member = Checklist(name: "Meeting", folderID: fileFolder.id)
        let (session, store) = makeSession()
        store.createFolder(name: "Work")   // local, isCollapsed: false

        _ = try session.stage(data: payload([member], folders: [fileFolder]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.folders.count == 1, "reuse never mints a duplicate")
        #expect(store.folders.first?.isCollapsed == false, "reuse keeps the local collapse state")
    }

    /// The file's `folderTombstones` are never read by the import flow: a
    /// tombstoned file folder does not delete the local same-name folder.
    @Test
    func fileFolderTombstoneIsIgnored() throws {
        let fileWork = Folder(name: "Work")
        let unrelated = Checklist(name: "Unrelated", folderID: fileWork.id)
        let tombstone = FolderTombstone(folderID: fileWork.id, deletedAt: Date(), revision: 9)
        let (session, store) = makeSession()
        store.createFolder(name: "Work")

        _ = try session.stage(data: payload([unrelated], folders: [fileWork],
                                            folderTombstones: [tombstone]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.folders.map(\.name) == ["Work"], "file folder tombstone is never applied")
        #expect(store.folderTombstones.isEmpty)
    }

    /// Two same-named file folders collapse to a single local folder; both
    /// member checklists point at it.
    @Test
    func twoSameNamedFoldersInOneFileCollapseToOne() throws {
        let fileA = Folder(name: "Work")
        let fileB = Folder(name: "Work")
        let memberA = Checklist(name: "A", folderID: fileA.id)
        let memberB = Checklist(name: "B", folderID: fileB.id)
        let (session, store) = makeSession()

        _ = try session.stage(data: payload([memberA, memberB], folders: [fileA, fileB]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.folders.count == 1)
        #expect(store.folders.map(\.name) == ["Work"], "duplicate-named file folders collapse to one")
        let folder = try #require(store.folders.first)
        #expect(store.checklists.count == 2)
        #expect(Set(store.checklists.compactMap(\.folderID)) == [folder.id], "both members share the single folder")
    }

    /// Import matches by name only: a locally renamed folder (no sameName match)
    /// coexists with the imported folder of that name. Documented consequence.
    @Test
    func renamedLocalFolderGetsANewFolderOnImport() throws {
        let fileFolder = Folder(name: "Groceries")
        let member = Checklist(name: "Groceries", folderID: fileFolder.id)
        let (session, store) = makeSession()
        store.createFolder(name: "Food")   // local renamed folder, not a sameName match

        _ = try session.stage(data: payload([member], folders: [fileFolder]))
        session.commit(selectedIDs: allIDs(session.candidates))

        #expect(store.folders.map(\.name) == ["Food", "Groceries"], "a renamed local folder coexists with the imported one")
    }

    /// The commit pre-resolution covers SELECTED candidates only: an unticked
    /// candidate's referenced folder is never minted.
    @Test
    func unselectedCandidatesFolderIsNotMinted() throws {
        let workFile = Folder(name: "Work")
        let homeFile = Folder(name: "Home")
        let picked = Checklist(name: "Picked", folderID: workFile.id)
        let skipped = Checklist(name: "Skipped", folderID: homeFile.id)
        let (session, store) = makeSession()

        _ = try session.stage(data: payload([picked, skipped], folders: [workFile, homeFile]))
        let pickedID = try #require(session.candidates.first { $0.checklist.name == "Picked" }?.id)
        session.commit(selectedIDs: [pickedID])

        #expect(store.folders.map(\.name) == ["Work"], "only the selected candidate's folder is minted")
        #expect(store.checklists.count == 1)
        #expect(store.checklists.first?.folderID == store.folders.first?.id)
    }
}
