import CheckStitchCore
import SwiftUI

struct WatchChecklistDetailView: View {
    let checklist: Checklist
    @Environment(WatchChecklistStore.self) private var store
    @State private var sent = false

    /// Blank rows are never turned into reminders, so the watch hides them too.
    private var visibleItems: [ChecklistItem] {
        checklist.items.filter { !$0.isBlank }
    }

    var body: some View {
        List(visibleItems) { item in
            Text(item.title)
        }
        .navigationTitle(checklist.name)
        .safeAreaInset(edge: .bottom) {
            Button(sent ? "Sent" : "Create reminders") {
                sent = store.run(checklist)
            }
            .disabled(sent || visibleItems.isEmpty)
        }
    }
}