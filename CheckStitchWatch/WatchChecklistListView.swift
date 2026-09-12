import CheckStitchCore
import SwiftUI

struct WatchChecklistListView: View {
    @Environment(WatchChecklistStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.checklists.isEmpty {
                    ContentUnavailableView(
                        "No checklists",
                        systemImage: "checklist",
                        description: Text("Open CheckStitch on your iPhone."))
                } else {
                    List(store.checklists) { checklist in
                        NavigationLink(checklist.name) {
                            WatchChecklistDetailView(checklist: checklist)
                        }
                    }
                }
            }
            .navigationTitle("Checklists")
        }
        .task {
            store.start()
            store.requestRefresh()
        }
    }
}