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
                        ForEach(viewModel.sections) { section in
                            Section {
                                ForEach(section.checklists) { checklist in
                                    NavigationLink(checklist.name) {
                                        WatchChecklistDetailView(checklist: checklist)
                                    }
                                }
                            } header: {
                                // Keep the flat (no-folder) watch list exactly as
                                // it was; a folder section shows its own name.
                                if section.folder != nil {
                                    Text(section.name ?? "")
                                }
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