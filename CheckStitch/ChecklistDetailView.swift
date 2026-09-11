import SwiftUI

/// Detail screen for one checklist, keyed by id rather than a `@Binding` into a
/// parent view's `@State`, so mutations go through `ChecklistStore`.
struct ChecklistDetailView: View {
    let checklistID: UUID

    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isRemoving = false

    var body: some View {
        if let checklist = store.checklist(id: checklistID) {
            Form {
                Section("Checklist name") {
                    TextField("Checklist name", text: nameBinding(for: checklistID))
                        .accessibilityIdentifier("checklistNameField")
                }
                Section("Items") {
                    ForEach(checklist.items) { item in
                        TextField("Item", text: titleBinding(checklistID: checklistID, itemID: item.id))
                    }
                    .onDelete { offsets in
                        store.removeItems(from: checklistID, at: offsets)
                    }
                }
                Section {
                    Button {
                        store.addItem(to: checklistID)
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                    }
                    .accessibilityIdentifier("addItemButton")
                    .checkStitchButton()

                    Button(role: .destructive) {
                        isRemoving = true
                        store.delete(id: checklistID)
                        dismiss()
                    } label: {
                        Label("Remove Checklist", systemImage: "trash")
                    }
                    .accessibilityIdentifier("removeChecklistButton")
                    .checkStitchButton()
                }
            }
            .navigationTitle("Edit checklist")
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .checkStitchButton()
                }
            }
        } else if !isRemoving {
            // Deleted elsewhere while this screen was on the stack. A delete
            // from this screen skips the message so the pop never flashes it.
            ContentUnavailableView("Checklist not found", systemImage: "trash")
        }
    }

    private func nameBinding(for id: UUID) -> Binding<String> {
        Binding(
            get: { store.checklist(id: id)?.name ?? "" },
            set: { store.rename(id: id, to: $0) }
        )
    }

    private func titleBinding(checklistID: UUID, itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.checklist(id: checklistID)?.items.first { $0.id == itemID }?.title ?? ""
            },
            set: { store.updateItem(checklistID: checklistID, itemID: itemID, title: $0) }
        )
    }
}