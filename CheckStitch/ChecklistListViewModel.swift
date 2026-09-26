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
            return store.checklists.filter { checklist in
                guard let folderID = checklist.folderID else { return true }
                return !known.contains(folderID)
            }
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

    func moveFolder(id: UUID, up: Bool) {
        guard let index = store.folders.firstIndex(where: { $0.id == id }) else { return }
        store.moveFolders(from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
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
}
