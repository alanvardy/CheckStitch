import CheckStitchCore
import SwiftUI

struct WatchChecklistListView: View {
    @Environment(WatchChecklistViewModel.self) private var viewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.checklists.isEmpty {
                    ContentUnavailableView(
                        "No checklists",
                        systemImage: "checklist",
                        description: Text("Open CheckStitch on your iPhone."))
                } else {
                    List {
                        // Folders are rows you tap into; their checklists live
                        // on `WatchFolderDetailView` so the top level stays short.
                        ForEach(viewModel.visibleFolders) { folder in
                            NavigationLink {
                                WatchFolderDetailView(folder: folder)
                            } label: {
                                Label(folder.name, systemImage: "folder")
                            }
                        }
                        // Loose checklists have no folder to open, so they stay
                        // direct rows (the flat list's original shape).
                        ForEach(viewModel.looseChecklists) { checklist in
                            NavigationLink(checklist.name) {
                                WatchChecklistDetailView(checklist: checklist)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Checklists")
        }
        .tint(.blue)
        .task {
            viewModel.onAppear()
        }
    }
}