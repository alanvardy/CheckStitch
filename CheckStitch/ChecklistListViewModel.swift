import CheckStitchCore
import Foundation
import Observation

/// Root list view model: owns the checklist list surface and its mutations.
/// The view reads `checklists` and forwards intent; navigation, animation and
/// dialogs stay in the view.
@MainActor
@Observable
final class ChecklistListViewModel {
    private let store: ChecklistStore

    init(store: ChecklistStore) {
        self.store = store
    }

    var checklists: [Checklist] { store.checklists }

    /// Folders in persisted order; `nil` is the loose group.
    var folders: [Folder] { store.folders }

    /// Members of `folder` in persisted global order. `nil` is the loose group:
    /// checklists with no folder, plus any whose `folderID` names a folder that is
    /// not (yet) known — cross-reference skew renders loose, never dropped.
    func checklists(in folder: Folder?) -> [Checklist] {
        guard let folder else {
            let known = Set(store.folders.map(\.id))
            return store.checklists.filter { ChecklistGrouping.isLoose($0, knownFolderIDs: known) }
        }
        return store.checklists.filter { $0.folderID == folder.id }
    }

    @discardableResult
    func createFolder(name: String? = nil) -> UUID {
        store.createFolder(name: name).id
    }

    func moveChecklist(id: UUID, toFolder folderID: UUID?) {
        store.moveChecklist(id: id, toFolder: folderID)
    }

    func renameFolder(id: UUID, to name: String) {
        store.renameFolder(id: id, to: name)
    }

    /// Collapses or expands one folder's members. Persisted and synced through
    /// the store's envelope, so the state survives relaunch and reaches iCloud.
    func setFolderCollapsed(id: UUID, _ isCollapsed: Bool) {
        store.setFolderCollapsed(id: id, isCollapsed)
    }

    func moveFolder(id: UUID, up: Bool) {
        guard let index = store.folders.firstIndex(where: { $0.id == id }) else { return }
        store.moveFolders(from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
    }

    /// Maps a folder drag onto the store's `folders` array. Same take-the-slot
    /// semantics as `moveChecklist(id:onto:)`; self-drops and unknown ids are
    /// silent no-ops. Folder order is the persisted array order, so no revision
    /// is stamped (mirrors `moveFolders`/`moveFolder(id:up:)`).
    func moveFolder(id: UUID, onto targetID: UUID) {
        guard id != targetID else { return }
        guard let from = store.folders.firstIndex(where: { $0.id == id }),
              let to = store.folders.firstIndex(where: { $0.id == targetID }) else { return }
        store.moveFolders(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
    }

    /// The folder waiting for its confirm/cancel in the delete dialog; `nil` hides it.
    var folderPendingRemoval: UUID?

    func removeFolder(id: UUID) {
        store.deleteFolder(id: id)
    }

    /// Creates a checklist and returns the new id. `store.create()` disambiguates
    /// a duplicate name ("New checklist 2") rather than failing, so there is
    /// always a checklist to open.
    @discardableResult
    func createChecklist() -> UUID {
        store.create().id
    }

    /// The checklist waiting for its confirm/cancel in the remove dialog; `nil`
    /// hides it.
    var checklistPendingRemoval: UUID?

    /// Performs the destructive half of the removal gate: a single-row batch
    /// into the store's `removeChecklists` (one tombstone, one save).
    func removeChecklist(id: UUID) {
        guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
        store.removeChecklists(at: IndexSet(integer: index))
    }

    /// Converts a one-row nudge into the `moved` index arithmetic: one row up is
    /// `destination == index - 1`, one row down is `index + 2` (adjusted for the
    /// removed element).
    func moveChecklist(id: UUID, up: Bool) {
        guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
        store.moveChecklists(from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
    }

    /// The section a checklist renders in: its folder id when that folder is
    /// known, otherwise nil (the loose group). Mirrors `checklists(in:)`/`isLoose`
    /// so a skewed (unknown) `folderID` gates as loose, exactly as it renders.
    private func sectionID(for checklist: Checklist) -> UUID? {
        guard let folderID = checklist.folderID,
              store.folders.contains(where: { $0.id == folderID }) else { return nil }
        return folderID
    }

    /// Maps a checklist drag onto the store's global `checklists` array. `targetID`
    /// is the row the drag entered: the dragged checklist takes that row's slot in
    /// its section, so a downward drag lands after the target and an upward drag
    /// before it. A single live-reorder drag calls this once per row entered, so
    /// each call persists a move. Cross-section drags, self-drops and unknown ids
    /// are silent no-ops — cross-folder filing stays with
    /// `moveChecklist(id:toFolder:)`.
    func moveChecklist(id: UUID, onto targetID: UUID) {
        guard id != targetID else { return }
        guard let from = store.checklists.firstIndex(where: { $0.id == id }),
              let to = store.checklists.firstIndex(where: { $0.id == targetID }) else { return }
        guard sectionID(for: store.checklists[from]) == sectionID(for: store.checklists[to]) else { return }
        store.moveChecklists(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
    }
}
