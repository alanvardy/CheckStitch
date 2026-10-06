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

    var folders: [Folder] { store.folders }

    /// Checklists with no folder (or a folder id the phone no longer knows), in
    /// global order, excluding any the phone has hidden. Rendered as top-level
    /// rows directly under the folder rows.
    var looseChecklists: [Checklist] {
        let known = Set(store.folders.map(\.id))
        return ChecklistGrouping.visibleLooseChecklists(store.checklists, knownFolderIDs: known)
    }

    /// Folders with at least one visible checklist, plus empty folders. A folder
    /// whose members are all hidden drops off the root list.
    var visibleFolders: [Folder] {
        ChecklistGrouping.visibleFolders(store.folders, checklists: store.checklists)
    }

    /// The checklists inside `folder`, in global order, excluding hidden ones.
    func checklists(in folder: Folder) -> [Checklist] {
        ChecklistGrouping.visibleChecklists(in: folder, from: store.checklists)
    }

    /// The live folder once a refresh lands, falling back to the pushed seed.
    func current(_ folder: Folder) -> Folder {
        store.folders.first { $0.id == folder.id } ?? folder
    }

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

    /// Blank rows and disabled rows are never turned into reminders, so the watch hides them too.
    func visibleItems(of checklist: Checklist) -> [ChecklistItem] {
        current(checklist).items.filter(\.isRunnable)
    }

    func phase(runID: UUID?) -> RunPhase {
        runID.map { store.runPhase(runID: $0) } ?? .idle
    }
}
