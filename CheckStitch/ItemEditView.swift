import CheckStitchCore
import SwiftUI

/// Edits one item's description and relative due date ("days until due").
///
/// Pushed from the edit affordance on an `ItemRow`. Reads the item from the
/// store each pass so an iCloud merge lands live, committing through the same
/// per-field mutators as the detail screen. The date field buffers its text
/// exactly like `ItemRow` (reusing its parse/format helpers) so a half-typed
/// `"-"` survives; the store no-ops an unchanged date.
struct ItemEditView: View {
    let checklistID: UUID
    let itemID: UUID

    @Environment(ChecklistStore.self) private var store
    @State private var draftDate = ""
    @State private var didLoadDraft = false

    var body: some View {
        Group {
            if let item = store.checklist(id: checklistID)?
                .items.first(where: { $0.id == itemID }) {
                Form {
                    Section {
                        TextField("Description", text: descriptionBinding, axis: .vertical)
                            .accessibilityIdentifier("itemEditDescriptionField")
                    }
                    Section {
                        dueDateField
                    } footer: {
                        caption("Leave empty for no due date. 0 means today.")
                    }
                }
                .onChange(of: item.relativeDate) { _, newValue in
                    // External (iCloud) change updates the buffer unless the
                    // buffer already represents it, matching `ItemRow`.
                    if let refreshed = ItemRow.draft(
                        afterExternalChange: newValue, current: draftDate) {
                        draftDate = refreshed
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
        .onAppear {
            guard !didLoadDraft else { return }
            let item = store.checklist(id: checklistID)?.items.first { $0.id == itemID }
            draftDate = ItemRow.format(item?.relativeDate)
            didLoadDraft = true
        }
        .onDisappear { store.flushPendingSave() }
    }

    /// Per-keystroke description write, mirroring `ChecklistDetailView`.
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

    /// The numbers-and-punctuation keyboard is iOS-only (macOS has no software
    /// keyboard) and is what keeps a leading `-` typeable; the chain is
    /// duplicated under the guard because SwiftUI modifier calls return
    /// distinct opaque view types, matching `ItemRow.dueDateField`.
    private var dueDateField: some View {
        #if os(iOS)
            TextField("Days", text: $draftDate)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("itemEditRelativeDateField")
                .onChange(of: draftDate) { _, newValue in
                    store.updateItem(
                        checklistID: checklistID, itemID: itemID,
                        relativeDate: ItemRow.parse(newValue))
                }
        #else
            TextField("Days", text: $draftDate)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("itemEditRelativeDateField")
                .onChange(of: draftDate) { _, newValue in
                    store.updateItem(
                        checklistID: checklistID, itemID: itemID,
                        relativeDate: ItemRow.parse(newValue))
                }
        #endif
    }

    @ViewBuilder
    private func caption(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
