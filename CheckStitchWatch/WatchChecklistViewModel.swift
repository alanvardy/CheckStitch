import CheckStitchCore
import Foundation
import Observation

/// Wraps the watch's `WatchChecklistStore` so the list/detail views only render
/// and delegate. EventKit stays phone-side.
@MainActor
@Observable
final class WatchChecklistViewModel {
    private let store: WatchChecklistStore

    init(store: WatchChecklistStore) {
        self.store = store
    }

    var checklists: [Checklist] { store.checklists }

    /// Activates the transport and asks the phone for a fresh snapshot.
    func onAppear() {
        store.start()
        store.requestRefresh()
    }

    /// Sends a run request and returns its run id (the detail screen tracks it).
    @discardableResult
    func run(_ checklist: Checklist) -> UUID {
        store.run(checklist)
    }

    /// The live store copy once a refresh lands, falling back to the pushed seed.
    func current(_ checklist: Checklist) -> Checklist {
        store.checklists.first { $0.id == checklist.id } ?? checklist
    }

    /// Blank rows are never turned into reminders, so the watch hides them too.
    func visibleItems(of checklist: Checklist) -> [ChecklistItem] {
        current(checklist).items.filter { !$0.isBlank }
    }

    func phase(runID: UUID?) -> RunPhase {
        runID.map { store.runPhase(runID: $0) } ?? .idle
    }
}
