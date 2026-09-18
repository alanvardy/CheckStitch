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
                    List(viewModel.checklists) { checklist in
                        NavigationLink(checklist.name) {
                            WatchChecklistDetailView(checklist: checklist)
                        }
                    }
                }
            }
            .navigationTitle("Checklists")
        }
        .task {
            viewModel.onAppear()
        }
    }
}