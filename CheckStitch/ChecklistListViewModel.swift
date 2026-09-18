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
}