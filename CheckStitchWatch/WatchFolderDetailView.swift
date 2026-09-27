import CheckStitchCore
import SwiftUI

/// The checklists filed under one folder. Reached by tapping a folder row on the
/// watch root; each row opens the usual checklist detail screen.
struct WatchFolderDetailView: View {
    let folder: Folder
    @Environment(WatchChecklistViewModel.self) private var viewModel

    /// Resolved through the view model so a refresh that renames the folder (or
    /// empties it) is reflected without a re-push of this screen.
    private var current: Folder {
        viewModel.current(folder)
    }

    private var members: [Checklist] {
        viewModel.checklists(in: current)
    }

    var body: some View {
        Group {
            if members.isEmpty {
                ContentUnavailableView("No checklists", systemImage: "checklist")
            } else {
                List(members) { checklist in
                    NavigationLink(checklist.name) {
                        WatchChecklistDetailView(checklist: checklist)
                    }
                }
            }
        }
        .navigationTitle(current.name)
    }
}