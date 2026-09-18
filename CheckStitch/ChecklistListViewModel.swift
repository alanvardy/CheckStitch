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