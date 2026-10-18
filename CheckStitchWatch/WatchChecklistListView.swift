import CheckStitchCore
import SwiftUI

struct WatchChecklistListView: View {
    var initialChecklistIndex: Int? = nil
    @Environment(WatchChecklistViewModel.self) private var viewModel
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if viewModel.visibleFolders.isEmpty && viewModel.looseChecklists.isEmpty {
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
            .navigationDestination(for: UUID.self) { id in
                if let checklist = viewModel.checklists.first(where: { $0.id == id }) {
                    WatchChecklistDetailView(checklist: checklist)
                }
            }
        }
        .tint(.blue)
        .task {
            viewModel.onAppear()
            if let index = initialChecklistIndex,
               viewModel.checklists.indices.contains(index) {
                path = [viewModel.checklists[index].id]
            }
        }
    }
}
