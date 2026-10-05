import CheckStitchCore
import SwiftUI

/// The only surface that lists archived checklists. Rows show the name and the
/// archive date. Tapping a row offers Restore or Delete Permanently; the same
/// two actions are also available as trailing swipe actions (Phase 4).
struct ArchivedChecklistsView: View {
    @Environment(ChecklistStore.self) private var store
    @State private var pendingAction: PendingAction?

    /// The row's tap or a swipe action, held until the dialog resolves. The
    /// `.options` step swaps to `.confirmDeletion` in place, so a permanent
    /// delete always takes a second, explicitly destructive choice.
    private enum PendingAction {
        case options(UUID)
        case confirmDeletion(UUID)

        var checklistID: UUID {
            switch self {
            case .options(let id), .confirmDeletion(let id): id
            }
        }
    }

    var body: some View {
        Form {
            if store.archivedChecklists.isEmpty {
                ContentUnavailableView("No Archived Checklists", systemImage: "archivebox")
            } else {
                ForEach(store.archivedChecklists) { checklist in
                    Button {
                        pendingAction = .options(checklist.id)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(checklist.name)
                            if let archivedAt = checklist.archivedAt {
                                Text("Archived \(archivedAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("archivedChecklistRow")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            pendingAction = .confirmDeletion(checklist.id)
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
            dialogTitle,
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { if !$0 { pendingAction = nil } }),
            presenting: pendingAction
        ) { action in
            switch action {
            case .options(let id):
                Button("Restore") { store.restore(id: id) }
                Button("Delete Permanently", role: .destructive) {
                    pendingAction = .confirmDeletion(id)
                }
                Button("Cancel", role: .cancel) { pendingAction = nil }
            case .confirmDeletion(let id):
                Button("Cancel", role: .cancel) { pendingAction = nil }
                Button("Delete Permanently", role: .destructive) {
                    store.removeArchived(id: id)
                    pendingAction = nil
                }
            }
        }
        .navigationTitle("Archived Checklists")
        .settingsSubscreenLayout()
    }

    /// The dialog carries the checklist's name, falling back to the screen title
    /// for the transient frame before the row's action resolves.
    private var dialogTitle: Text {
        guard let id = pendingAction?.checklistID,
              let name = store.archivedChecklists.first(where: { $0.id == id })?.name
        else { return Text("Archived Checklists") }
        return Text(name)
    }
}

#Preview {
    NavigationStack {
        ArchivedChecklistsView()
    }
}
