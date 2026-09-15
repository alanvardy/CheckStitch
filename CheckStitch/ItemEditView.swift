import CheckStitchCore
import SwiftUI

/// Edits one item's title, description and relative due date ("days until
/// due").
///
/// Pushed from an `ItemRow` — the whole row is the link. Reads the item from the
/// store each pass so an iCloud merge lands live, committing through the same
/// per-field mutators as the detail screen. The date field buffers its text (see
/// `RelativeDateDraft`) so a half-typed `"-"` survives; the store no-ops an
/// unchanged date.
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
                    Section("Title") {
                        TextField("Title", text: titleBinding, axis: .vertical)
                            .accessibilityIdentifier("itemEditTitleField")
                    }
                    Section("Description") {
                        TextField("Description", text: descriptionBinding, axis: .vertical)
                            .accessibilityIdentifier("itemEditDescriptionField")
                    }
                    Section {
                        dueDateField
                    } header: {
                        Text("Due date")
                    } footer: {
                        Text("0 means today, 1 means tomorrow, nothing means no date.")
                    }
                }
                .onChange(of: item.relativeDate) { _, newValue in
                    // An external (iCloud) change updates the buffer only when
                    // it differs from what the buffer already represents, so a
                    // padded `"05"` or a half-typed `"-"` is never rewritten.
                    if let refreshed = RelativeDateDraft.text(
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
            draftDate = RelativeDateDraft.text(for: item?.relativeDate)
            didLoadDraft = true
        }
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

    /// The typed day count: empty is "no date", a whole number is the offset.
    /// Only complete values are committed, so a half-typed `"-"` never clears
    /// the stored date. The numbers-and-punctuation keyboard is iOS-only (macOS
    /// has no software keyboard) and is what keeps a leading `-` typeable; the
    /// chain is duplicated under the guard because SwiftUI modifier calls return
    /// distinct opaque view types.
    private var dueDateField: some View {
        #if os(iOS)
            TextField("Due date", text: $draftDate)
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("itemEditDueDateField")
                .onChange(of: draftDate) { _, newValue in commitDate(newValue) }
        #else
            TextField("Due date", text: $draftDate)
                .multilineTextAlignment(.trailing)
                .accessibilityIdentifier("itemEditDueDateField")
                .onChange(of: draftDate) { _, newValue in commitDate(newValue) }
        #endif
    }

    /// Commits the field's text through the store; in-progress text (a lone
    /// `"-"`) is left for the next keystroke, and the store no-ops an unchanged
    /// value.
    private func commitDate(_ text: String) {
        guard case .value(let relativeDate) = RelativeDateDraft.commit(for: text) else { return }
        store.updateItem(checklistID: checklistID, itemID: itemID, relativeDate: relativeDate)
    }
}
