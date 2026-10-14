import CheckStitchCore
import SwiftUI

/// The two scaling modes as a `Hashable` picker selection. `Scaling` carries an
/// associated number, so the `Picker` tags on this value instead, mapping to and
/// from `Scaling` through `Scaling.toggled()`.
private enum ScalingMode: Hashable { case fixed, prompt }

/// The checklist's less frequently changed settings, pushed from the edit
/// screen so its form stays short: destination list, reminder numbering,
/// scaling, and watch visibility. Every value reads and writes through
/// `ChecklistStore`, exactly as it did on the edit screen.
struct ChecklistOptionsView: View {
    let checklistID: UUID

    @Environment(ChecklistStore.self) private var store
    /// The enumerated lists at one instant. Read through `selectableOptions`,
    /// which drops the system default: the "Default (Inbox)" row below already
    /// stands for that list, and EventKit returns it like any other, so listing
    /// it again would show the same destination twice.
    @State private var listsSnapshot: ReminderListsSnapshot?
    /// True when Reminders access was denied, threw, or returned no lists: the
    /// picker degrades to the default-only row with an explanatory note.
    @State private var destinationUnavailable = false

    var body: some View {
        GeometryReader { geometry in
            if store.checklist(id: checklistID) != nil {
                Form {
                    Section {
                        Picker("List", selection: destinationBinding(checklistID: checklistID)) {
                            Text("Default (Inbox)").tag(ChecklistDestination.systemDefault)
                            Text("Ask me each time").tag(ChecklistDestination.prompt)
                            ForEach(listsSnapshot?.selectableOptions ?? []) { list in
                                Text(list.title).tag(ChecklistDestination.list(list.id))
                            }
                        }
                        .accessibilityIdentifier("destinationListPicker")
                    } footer: {
                        Text("The Reminders list where the new reminders will be added.")

                        if destinationUnavailable {
                            Text("Reminder lists aren't available, so a destination can't be chosen here.")
                        } else if destinationIsStale {
                            Text("The previously selected list no longer exists. Choose another list or Default (Inbox).")
                        }
                    }
                    Section {
                        Toggle(isOn: showOnWatchBinding(checklistID: checklistID)) {
                            Label("Show on watch", systemImage: "applewatch")
                        }
                        .accessibilityIdentifier("checklistShowsOnWatchToggle")
                    } footer: {
                        Text("Hidden checklists stay on your iPhone but are not shown on the Apple Watch.")
                    }
                    Section {
                        Toggle(isOn: numberingBinding(checklistID: checklistID)) {
                            Label("Number reminders", systemImage: "textformat.123")
                        }
                        .accessibilityIdentifier("checklistPrefixNumbersToggle")
                    } footer: {
                        Text("Prefix each reminder title with its position, like \"1: Buy milk\".")
                    }
                    Section {
                        LabeledContent("Scaling") {
                            Picker("Scaling", selection: scalingModeBinding(checklistID: checklistID)) {
                                Text("Fixed").tag(ScalingMode.fixed)
                                Text("Prompt").tag(ScalingMode.prompt)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityIdentifier("checklistScalingModePicker")
                        }
                        if store.checklist(id: checklistID)?.scaling.isPrompt != true {
                            scalingField(checklistID: checklistID)
                        }
                    } footer: {
                        Text("Scaling multiplies any integer in double brackets — e.g. ((2)) becomes 6 at Scaling 3. The brackets are removed.")
                    }
                }
                .navigationTitle("Checklist Options")
                .toolbarTitleDisplayMode(.inline)
                .settingsSubscreenLayout()
                .checklistEditFormWidth(viewportWidth: geometry.size.width)
                .onAppear { Task { await loadReminderLists() } }
            } else {
                // Deleted elsewhere (e.g. an iCloud merge) while this screen was on
                // the stack: mirror `ChecklistDetailView`'s placeholder rather than
                // binding a form to a missing checklist.
                ContentUnavailableView("Checklist not found", systemImage: "trash")
            }
        }
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
              case .list(let id) = store.checklist(id: checklistID)?.destination,
              listsSnapshot.pickerSelection(for: id) != nil
        else { return false }
        return !listsSnapshot.selectableOptions.contains { $0.id == id }
    }

    /// Per-selection write through the store for the numbering toggle. The
    /// getter reads the store so a value that arrives over sync updates the
    /// toggle; `.notFound` (deleted while this screen was open) is ignored,
    /// matching `destinationBinding`.
    private func numberingBinding(checklistID: UUID) -> Binding<Bool> {
        Binding(
            get: { store.checklist(id: checklistID)?.prefixesReminderNumbers ?? false },
            set: { store.setPrefixesReminderNumbers($0, for: checklistID) }
        )
    }

    /// Per-selection write through the store for the scaling mode. Switching
    /// modes keeps the current number (`Scaling.toggled()`); the getter reads
    /// the store so a mode arriving over sync updates the picker. `.notFound`
    /// (deleted while this screen was open) is ignored, matching
    /// `numberingBinding`.
    private func scalingModeBinding(checklistID: UUID) -> Binding<ScalingMode> {
        Binding(
            get: { (store.checklist(id: checklistID)?.scaling.isPrompt ?? false) ? .prompt : .fixed },
            set: { mode in
                guard let current = store.checklist(id: checklistID)?.scaling else { return }
                let wantsPrompt = (mode == .prompt)
                guard wantsPrompt != current.isPrompt else { return }
                store.setScaling(current.toggled(), for: checklistID)
            }
        )
    }

    /// The fixed factor, read/written through the store. Only rendered for
    /// `.fixed`.
    private func multipleBinding(checklistID: UUID) -> Binding<Int> {
        Binding(
            get: { store.checklist(id: checklistID)?.scaling.number ?? 1 },
            set: { store.setScaling(.fixed($0), for: checklistID) }
        )
    }

    /// The Scaling factor as a typed number rather than a stepper. iOS gets a
    /// number pad; macOS has no software keyboard, so the chain is duplicated
    /// under the guard because SwiftUI modifier calls return distinct opaque
    /// view types, matching `ItemEditView.dueDateField`. The store clamps a
    /// typed out-of-range value into `Checklist.multipleRange`.
    @ViewBuilder
    private func scalingField(checklistID: UUID) -> some View {
        LabeledContent("Factor") {
            #if os(iOS)
                TextField("Factor", value: multipleBinding(checklistID: checklistID),
                          format: .number)
                    .labelsHidden()
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .accessibilityHint(Text(
                        "Scale item markers by this factor when creating reminders."))
                    .accessibilityIdentifier("checklistScalingField")
            #else
                TextField("Factor", value: multipleBinding(checklistID: checklistID),
                          format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .accessibilityHint(Text(
                        "Scale item markers by this factor when creating reminders."))
                    .accessibilityIdentifier("checklistScalingField")
            #endif
        }
    }

    /// Per-selection write through the store for the "Show on watch" toggle. The
    /// getter reads the store so a value that arrives over sync updates the
    /// toggle; `.notFound` (deleted while this screen was open) is ignored,
    /// matching `numberingBinding`.
    private func showOnWatchBinding(checklistID: UUID) -> Binding<Bool> {
        Binding(
            get: { store.checklist(id: checklistID)?.showsOnWatch ?? true },
            set: { store.setShowsOnWatch($0, for: checklistID) }
        )
    }

    /// Per-selection write through the store. `.systemDefault` is the "Default
    /// (Inbox)" row. `.notFound` (deleted while this screen was open) is ignored,
    /// matching `commitDraftIfChanged`.
    private func destinationBinding(checklistID: UUID) -> Binding<ChecklistDestination> {
        Binding(
            get: {
                let stored = store.checklist(id: checklistID)?.destination ?? .systemDefault
                // A stored id that *is* the system default renders as the default row.
                if case .list(let id) = stored, let listsSnapshot,
                   listsSnapshot.pickerSelection(for: id) == nil {
                    return .systemDefault
                }
                return stored
            },
            set: { store.setDestination($0, for: checklistID) }
        )
    }
}
