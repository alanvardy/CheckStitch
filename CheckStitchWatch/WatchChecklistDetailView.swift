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
            VStack(alignment: .leading) {
                Text(item.title)
                if item.hasDescription {
                    Text(item.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(checklist.name)
        .safeAreaInset(edge: .bottom) {
            Button(sent
                ? String(localized: "Sent", table: "Localizable", bundle: .main)
                : String(localized: "Create reminders", table: "Localizable", bundle: .main)) {
                sent = store.run(checklist) != nil
            }
            .disabled(sent || visibleItems.isEmpty)
        }
    }
}