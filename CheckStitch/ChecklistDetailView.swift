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
    /// Gates the archive action behind the confirmation dialog: the archive
    /// button only raises this, and the dialog's button performs the archive.
    @State private var isArchiveConfirmPresented = false
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
    /// The add-item flow asks for the name first, so the button only raises
    /// this alert and never creates anything itself.
    @State private var isAddItemPresented = false
    /// Buffered item name for that alert.
    @State private var addItemDraftName = ""

    var body: some View {
        GeometryReader { geometry in
            if let checklist = store.checklist(id: checklistID) {
                Form {
                    Section("Checklist name") {
                        TextField("Name", text: $draftName)
                            .accessibilityIdentifier("checklistNameField")
                    }
                    Section {
                        NavigationLink {
                            ChecklistOptionsView(checklistID: checklistID)
                        } label: {
                            Label("Checklist Options", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("checklistOptionsLink")
                    }
                    Section("Items") {
                        ForEach(checklist.items) { item in
                            ItemRow(
                                checklistID: checklistID,
                                itemID: item.id,
                                title: item.title,
                                description: item.description,
                                scaling: checklist.scaling,
                                relativeDate: item.relativeDate,
                                priority: item.priority,
                                isEnabled: item.isEnabled,
                                onToggleEnabled: {
                                    store.updateItem(checklistID: checklistID, itemID: item.id, isEnabled: !item.isEnabled)
                                }
                            )
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
                            addItemDraftName = ""
                            isAddItemPresented = true
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

                        // The confirmation dialog lives on the button itself,
                        // not the enclosing Form: it renders as a popover
                        // anchored to the view it is attached to, so a Form-level
                        // attachment points the bubble at the top of the screen
                        // instead of the tapped button.
                        Button {
                            isArchiveConfirmPresented = true
                        } label: {
                            Label("Archive Checklist", systemImage: "archivebox")
                        }
                        .accessibilityIdentifier("archiveChecklistButton")
                        .checkStitchButton()
                        .confirmationDialog("Archive this checklist?", isPresented: $isArchiveConfirmPresented) {
                            Button("Cancel", role: .cancel) {}
                            Button("Archive Checklist", role: .destructive) {
                                store.archive(id: checklistID)
                                dismiss()
                            }
                            .accessibilityIdentifier("confirmArchiveChecklistButton")
                        } message: {
                            Text("You can restore it later from Settings.")
                        }

                        Button(role: .destructive) {
                            isRemoveConfirmPresented = true
                        } label: {
                            Label("Remove Checklist", systemImage: "trash")
                        }
                        .accessibilityIdentifier("removeChecklistButton")
                        .checkStitchButton()
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
                .alert("Add Item", isPresented: $isAddItemPresented) {
                    TextField("Name", text: $addItemDraftName)
                        .accessibilityIdentifier("addItemNameField")
                    Button("Cancel", role: .cancel) {}
                        .accessibilityIdentifier("cancelAddItemButton")
                    Button("Add") {
                        store.addItem(to: checklistID, title: addItemDraftName)
                    }
                    .accessibilityIdentifier("confirmAddItemButton")
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
                .checklistEditFormWidth(viewportWidth: geometry.size.width)
            } else if !isRemoving {
                // Deleted elsewhere while this screen was on the stack. A delete
                // from this screen skips the message so the pop never flashes it.
                ContentUnavailableView("Checklist not found", systemImage: "trash")
            }
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
}

/// One item row: the item's priority marker, its title, its human-readable due
/// date and its description, all read-only. A leading checkbox toggles the
/// item's enabled state without navigating. The checkbox sits **outside** the
/// `NavigationLink` label: an inline `Toggle` or `Button` inside a link's label
/// is inert, and tapping it would trigger the push. The rest of the row is the
/// link into the pushed `ItemEditView`, so the tap target is the row rather
/// than a small pencil icon. That is why the row no longer hosts editable
/// fields: a `NavigationLink` row makes its inline controls inert, so
/// title/description editing moved onto the edit screen with the date.
struct ItemRow: View {
    let checklistID: UUID
    let itemID: UUID
    let title: String
    let description: String
    let scaling: Scaling
    let relativeDate: Int?
    let priority: ChecklistItemPriority
    let isEnabled: Bool
    let onToggleEnabled: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggleEnabled) {
                Image(systemName: isEnabled ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Include in reminders"))
            .accessibilityIdentifier("itemEnabledToggle-\(itemID.uuidString)")

            NavigationLink {
                ItemEditView(checklistID: checklistID, itemID: itemID)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // The coloured exclamation marker SingleThread uses: the
                        // same font as the title, only the level's colour
                        // (red/yellow/green) distinguishes high/medium/low. No
                        // marker for an unprioritised item, so its row is
                        // unchanged.
                        if !priority.marker.isEmpty {
                            Text(priority.marker)
                                .font(.body)
                                .foregroundStyle(Self.priorityColor(priority))
                                .accessibilityLabel(Text(priority.label))
                                .accessibilityIdentifier("priorityMarker")
                        }
                        Text(Self.displayTitle(ChecklistScaling.resolve(title, multiple: scaling.number)))
                        Spacer(minLength: 0)
                        if Self.showsScalingFactor(scaling) {
                            // The `×`-leading key cannot be a string-symbol source
                            // (Xcode's GenerateStringSymbols can't derive a Swift
                            // identifier from `×%lld`), so resolve it at runtime
                            // against the App catalog and format the factor in.
                            Text(verbatim: String(
                                format: Bundle.main.localizedString(forKey: "×%lld", value: "×%lld", table: "Localizable"),
                                scaling.number))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("scalingFactorBadge")
                        }
                        // Blank when the item carries no date, per the product ask.
                        Text(DueDateLabel.resource(for: relativeDate))
                            .foregroundStyle(.secondary)
                    }
                    if !description.isEmpty {
                        Text(ChecklistScaling.resolve(description, multiple: scaling.number))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Disabled rows dim; the app never marks items complete, so
                // no strikethrough.
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            }
        }
        .accessibilityIdentifier("itemRow-\(itemID.uuidString)")
    }

    /// The marker colour per priority level, matching `SingleThread`'s
    /// red/yellow/green so the two apps read the same at a glance.
    static func priorityColor(_ priority: ChecklistItemPriority) -> Color {
        switch priority {
        case .none: .secondary
        case .low: .green
        case .medium: .yellow
        case .high: .red
        }
    }

    /// The `×N` factor badge is only meaningful when scaling actually changes marker
    /// text, so it is hidden at the neutral value and in Prompt mode.
    static func showsScalingFactor(_ scaling: Scaling) -> Bool {
        if case .fixed(let value) = scaling { return value > 1 }
        return false
    }

    /// The row's title. An empty title (the user cleared it on the edit screen)
    /// would otherwise leave the row rendering blank, so it falls back to the
    /// same "Item" placeholder the old inline field carried. Resolved against
    /// the persisted app language: a static helper has no environment locale.
    static func displayTitle(_ title: String) -> String {
        title.isEmpty
            ? LocalizedStringResource("Item", table: "Localizable", bundle: .main)
                .resolvedInAppLanguage()
            : title
    }
}
