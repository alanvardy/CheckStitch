import CheckStitchCore
import SwiftUI

/// Edits one item's title, description and relative due date.
///
/// Pushed from an `ItemRow` — the whole row is the link. Reads the item from the
/// store each pass so an iCloud merge lands live, committing through the same
/// per-field mutators as the detail screen.
struct ItemEditView: View {
    let checklistID: UUID
    let itemID: UUID

    @Environment(ChecklistStore.self) private var store

    var body: some View {
        Group {
            if let item = store.checklist(id: checklistID)?
                .items.first(where: { $0.id == itemID }) {
                Form {
                    Section {
                        TextField("Item", text: titleBinding, axis: .vertical)
                            .accessibilityIdentifier("itemEditTitleField")
                    }
                    Section {
                        TextField("Description", text: descriptionBinding, axis: .vertical)
                            .accessibilityIdentifier("itemEditDescriptionField")
                    }
                    Section {
                        dueDatePicker(current: item.relativeDate)
                    }
                }
            } else {
                // Deleted elsewhere (e.g. an iCloud merge) while on the stack.
                ContentUnavailableView("Item not found", systemImage: "trash")
            }
        }
        .navigationTitle("Edit item")
        .toolbarTitleDisplayMode(.inline)
        .settingsSubscreenLayout()
        .onDisappear { store.flushPendingSave() }
    }

    /// Per-keystroke title write, mirroring `ChecklistDetailView`'s helpers. The
    /// getter re-finds the item by id each read; a missing checklist/item reads
    /// as "".
    private var titleBinding: Binding<String> {
        Binding(
            get: {
                store.checklist(id: checklistID)?
                    .items.first { $0.id == itemID }?.title ?? ""
            },
            set: {
                store.updateItem(checklistID: checklistID, itemID: itemID, title: $0)
            }
        )
    }

    /// Per-keystroke description write, mirroring `titleBinding`.
    private var descriptionBinding: Binding<String> {
        Binding(
            get: {
                store.checklist(id: checklistID)?
                    .items.first { $0.id == itemID }?.description ?? ""
            },
            set: {
                store.updateItemDescription(
                    checklistID: checklistID, itemID: itemID, description: $0)
            }
        )
    }

    /// The due-date row: a menu of spelled-out offsets rather than a typed day
    /// count, so a bare `0` is never shown. `nil` is "No date". An offset the
    /// item already carries that is not one of the presets keeps its own row, so
    /// a value synced in from a device running an older build is displayed
    /// rather than silently rewritten to the nearest preset.
    private func dueDatePicker(current: Int?) -> some View {
        Picker("Due date", selection: relativeDateBinding) {
            Text("No date").tag(Int?.none)
            ForEach(DueDateLabel.presets, id: \.self) { offset in
                Text(DueDateLabel.text(for: offset)).tag(Int?.some(offset))
            }
            if let current, !DueDateLabel.presets.contains(current) {
                Text(DueDateLabel.text(for: current)).tag(Int?.some(current))
            }
        }
        .accessibilityIdentifier("itemEditDueDatePicker")
    }

    /// Per-selection write through the store, which no-ops an unchanged value.
    private var relativeDateBinding: Binding<Int?> {
        Binding(
            get: {
                store.checklist(id: checklistID)?
                    .items.first { $0.id == itemID }?.relativeDate
            },
            set: {
                store.updateItem(checklistID: checklistID, itemID: itemID, relativeDate: $0)
            }
        )
    }
}
