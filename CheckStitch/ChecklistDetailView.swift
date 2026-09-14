import CheckStitchCore
import SwiftUI

/// Detail screen for one checklist, keyed by id rather than a `@Binding` into a
/// parent view's `@State`, so mutations go through `ChecklistStore`.
struct ChecklistDetailView: View {
    let checklistID: UUID

    @Environment(ChecklistStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var isRemoving = false
    /// Gates deletion behind the confirmation dialog: the remove button only
    /// raises this, and the dialog's destructive button performs the removal.
    @State private var isRemoveConfirmPresented = false
    /// Buffered copy of the name field. The rename is validated and committed
    /// from here — on Done, or when the screen is left — instead of per
    /// keystroke, so typing a name another checklist owns does not raise an
    /// alert while the user is still editing it.
    @State private var draftName = ""
    @State private var didLoadDraft = false
    @State private var isNameConflictPresented = false
    /// The duplicate flow asks for the copy's name first, so the button only
    /// raises this alert and never creates anything itself.
    @State private var isDuplicatePresented = false
    /// Buffered copy name for that alert, seeded from the source name when the
    /// alert is raised.
    @State private var duplicateDraftName = ""
    /// The enumerated lists at one instant. Read through `selectableOptions`,
    /// which drops the system default: the "Default (Inbox)" row below already
    /// stands for that list, and EventKit returns it like any other, so listing
    /// it again would show the same destination twice.
    @State private var listsSnapshot: ReminderListsSnapshot?
    /// True when Reminders access was denied, threw, or returned no lists: the
    /// picker degrades to the default-only row with an explanatory note.
    @State private var destinationUnavailable = false

    var body: some View {
        if let checklist = store.checklist(id: checklistID) {
            Form {
                Section("Checklist name") {
                    TextField("Name", text: $draftName)
                        .accessibilityIdentifier("checklistNameField")
                }
                Section("Destination list") {
                    Picker("List", selection: destinationBinding(checklistID: checklistID)) {
                        Text("Default (Inbox)").tag(String?.none)
                        ForEach(listsSnapshot?.selectableOptions ?? []) { list in
                            Text(list.title).tag(String?.some(list.id))
                        }
                    }
                    .accessibilityIdentifier("destinationListPicker")

                    if destinationUnavailable {
                        Text("Reminder lists aren't available, so a destination can't be chosen here.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else if destinationIsStale {
                        Text("The previously selected list no longer exists. Choose another list or Default (Inbox).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Items") {
                    ForEach(checklist.items) { item in
                        TextField("Item", text: titleBinding(checklistID: checklistID, itemID: item.id))
                    }
                    .onDelete { offsets in
                        store.removeItems(from: checklistID, at: offsets)
                    }
                    .onMove { offsets, destination in
                        store.moveItems(checklistID: checklistID, from: offsets, to: destination)
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

                    Button {
                        duplicateDraftName = ChecklistStore.duplicateName(basedOn: checklist.name)
                        isDuplicatePresented = true
                    } label: {
                        Label("Duplicate Checklist", systemImage: "doc.on.doc")
                    }
                    .accessibilityIdentifier("duplicateChecklistButton")
                    .checkStitchButton()

                    Button(role: .destructive) {
                        isRemoveConfirmPresented = true
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
                #if os(iOS)
                // `EditButton` is unavailable on macOS, so the edit-mode toggle
                // is iOS-only; macOS reorders by drag without edit mode.
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                #endif
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { commitRename() }
                        // iOS 26 wraps bar items in a system glass container.
                        // `fixedSize()` stops it collapsing that container to
                        // a circle that clips the title, so "Done" keeps its
                        // natural width. Deliberately no `checkStitchButton()`:
                        // that modifier drops form-button chrome, but in a bar
                        // the native styling owns the shape.
                        .fixedSize()
                }
            }
            .onAppear {
                guard !didLoadDraft else { return }
                draftName = checklist.name
                didLoadDraft = true
                Task { await loadReminderLists() }
            }
            .onDisappear {
                // Leaving without Done still keeps a valid edit; a conflicting
                // one is dropped rather than alerted after the screen is gone.
                commitDraftIfChanged()
                store.flushPendingSave()
            }
            .alert("Name already in use", isPresented: $isNameConflictPresented) {
                Button("OK", role: .cancel) {}
                    .accessibilityIdentifier("renameNameConflictButton")
            } message: {
                Text("Another checklist already uses \(draftName) — choose a different name.")
            }
            .alert("Duplicate Checklist", isPresented: $isDuplicatePresented) {
                TextField("Name", text: $duplicateDraftName)
                    .accessibilityIdentifier("duplicateChecklistNameField")
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelDuplicateChecklistButton")
                Button("Duplicate") {
                    store.duplicate(id: checklistID, name: duplicateDraftName)
                }
                .accessibilityIdentifier("confirmDuplicateChecklistButton")
            } message: {
                Text("Creates a copy with the same items.")
            }
            .confirmationDialog("Remove Checklist", isPresented: $isRemoveConfirmPresented) {
                Button("Cancel", role: .cancel) {}
                    .accessibilityIdentifier("cancelRemoveChecklistButton")
                Button("Remove", role: .destructive) {
                    isRemoving = true
                    store.delete(id: checklistID)
                    dismiss()
                }
                .accessibilityIdentifier("confirmRemoveChecklistButton")
            } message: {
                Text("This removes the checklist and all its items.")
            }
        } else if !isRemoving {
            // Deleted elsewhere while this screen was on the stack. A delete
            // from this screen skips the message so the pop never flashes it.
            ContentUnavailableView("Checklist not found", systemImage: "trash")
        }
    }

    /// Done: apply the buffered name and dismiss, or keep the screen up and
    /// surface the conflict so the user can pick a different name.
    private func commitRename() {
        switch store.rename(id: checklistID, to: draftName) {
        case .renamed, .notFound:
            dismiss()
        case .nameTaken:
            isNameConflictPresented = true
        }
    }

    /// Backing out should not silently drop a valid rename, so commit the draft
    /// on the way out when it differs from what is stored. Outcomes are
    /// deliberately ignored here: a conflict has no screen left to explain it.
    private func commitDraftIfChanged() {
        guard store.checklist(id: checklistID)?.name != draftName else { return }
        store.rename(id: checklistID, to: draftName)
    }

    private func titleBinding(checklistID: UUID, itemID: UUID) -> Binding<String> {
        Binding(
            get: {
                store.checklist(id: checklistID)?.items.first { $0.id == itemID }?.title ?? ""
            },
            set: { store.updateItem(checklistID: checklistID, itemID: itemID, title: $0) }
        )
    }

    /// Enumerates the Reminders lists for the picker. Denied access, a thrown
    /// error, or an empty enumeration leaves the default-only row plus the note.
    private func loadReminderLists() async {
        let destination = EventKitReminderDestination.shared
        do {
            guard try await destination.requestAccess() else {
                destinationUnavailable = true
                return
            }
            let snapshot = try await destination.reminderLists()
            listsSnapshot = snapshot
            destinationUnavailable = snapshot.options.isEmpty
        } catch {
            destinationUnavailable = true
        }
    }

    /// True when the stored destination is no longer among the enumerated lists
    /// (deleted in Reminders while this screen was open), so the picker would
    /// otherwise render no selection without explanation. A destination that is
    /// the system default is never stale: the default row still represents it.
    private var destinationIsStale: Bool {
        guard !destinationUnavailable,
              let listsSnapshot,
              let destination = store.checklist(id: checklistID)?.destinationListIdentifier,
              listsSnapshot.pickerSelection(for: destination) != nil
        else { return false }
        return !listsSnapshot.selectableOptions.contains { $0.id == destination }
    }

    /// Per-selection write through the store (Phase 2). `nil` is the "Default
    /// (Inbox)" row. `.notFound` (deleted while this screen was open) is ignored,
    /// matching `commitDraftIfChanged`.
    private func destinationBinding(checklistID: UUID) -> Binding<String?> {
        Binding(
            get: {
                let stored = store.checklist(id: checklistID)?.destinationListIdentifier
                // A destination that is the system default is shown by the
                // default row, which is the only row now carrying that list.
                guard let listsSnapshot else { return stored }
                return listsSnapshot.pickerSelection(for: stored)
            },
            set: { store.setDestination($0, for: checklistID) }
        )
    }
}
