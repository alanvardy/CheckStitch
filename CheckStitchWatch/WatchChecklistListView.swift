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
                                // it was; label the loose section only once folders
                                // exist.
                                if section.folder != nil {
                                    Text(section.name ?? "")
                                } else if viewModel.sections.count > 1 {
                                    Text("Loose")
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