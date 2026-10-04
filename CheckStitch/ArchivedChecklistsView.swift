import CheckStitchCore
import SwiftUI

/// The only surface that lists archived checklists. Rows show the name and the
/// archive date; swipe to Restore or Delete Permanently (Phase 4).
struct ArchivedChecklistsView: View {
    @Environment(ChecklistStore.self) private var store
    @State private var pendingDeletion: UUID?

    var body: some View {
        Form {
            if store.archivedChecklists.isEmpty {
                ContentUnavailableView("No Archived Checklists", systemImage: "archivebox")
            } else {
                ForEach(store.archivedChecklists) { checklist in
                    VStack(alignment: .leading) {
                        Text(checklist.name)
                        if let archivedAt = checklist.archivedAt {
                            Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingDeletion = checklist.id
                        } label: {
                            Label("Delete Permanently", systemImage: "trash")
                        }
                        Button {
                            store.restore(id: checklist.id)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.blue)
                    }
                }
            }
        }
        .confirmationDialog(
            "Delete Permanently",
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { id in
            Button("Cancel", role: .cancel) { pendingDeletion = nil }
            Button("Delete Permanently", role: .destructive) {
                store.removeArchived(id: id)
                pendingDeletion = nil
            }
        }
        .navigationTitle("Archived Checklists")
        .settingsSubscreenLayout()
    }
}

#Preview {
    NavigationStack {
        ArchivedChecklistsView()
    }
}
