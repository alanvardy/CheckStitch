# Implementation Plan

## Overview

Add a pushed **Checklist Options** subscreen (`ChecklistOptionsView`) reachable
from a `NavigationLink` row under the checklist-name section of
`ChecklistDetailView`, and move the five controls — Destination list, Number
Reminders, Scaling, Factor and Show on watch — onto it. This is a pure UI
relocation: every control keeps its existing `ChecklistStore` binding and
accessibility identifier, so the underlying values and behaviour are unchanged.

Shape of the change: one new app-target view file (no `project.pbxproj` edit —
the target uses `PBXFileSystemSynchronizedRootGroup`), one new `NavigationLink`
push in the detail form, the five `Section`s plus their private state/binding
helpers deleted from `ChecklistDetailView`, one new localized key in six
languages plus a fixture entry, and a new render-smoke test file.

Recon corrections to `medium.md`:
- **No `ContentView.swift` change is needed.** `ChecklistDetailView`'s Items
  rows already push via a destination-closure `NavigationLink`
  (`ChecklistDetailView.swift:439`), which works inside the existing
  `NavigationStack(path:)`. A closure push is the established precedent for a
  subscreen, not an added route value.
- `ScalingMode` and every binding helper are used **only** by the five moved
  sections, so they move wholesale; `loadReminderLists()` /
  `destinationIsStale` / `listsSnapshot` / `destinationUnavailable` move with
  the Destination section and `onAppear`.
- The 28 `ChecklistDetailViewTests` do **not** assert the moved controls or
  their state slots (they assert dialog slots, render passes and store
  mutators), so they should stay green without edits. The plan still extends the
  test surface additively.
- New screen follows the `settingsSubscreenLayout()` precedent
  (`Form` + `.navigationTitle(...)` + `.settingsSubscreenLayout()`, as in
  `ArchivedChecklistsView.swift:84-86`), so no `checklistEditFormWidth`.

---

## Phase 1: Checklist Options screen, reachable and localized (walking skeleton)

Introduce the new screen with all five controls wired to their existing store
bindings, push it from the edit screen, and add the new localized key. The five
controls still also exist on the edit screen at the end of this phase; Phase 2
removes them, so this phase is a real end-to-end path (navigate → change a
value → store persists) that leaves the tree green.

### Changes

#### 1. New options screen
**File**: `CheckStitch/ChecklistOptionsView.swift`
**Action**: create

The file-scope `ScalingMode` enum and every moved helper are copied here from
`ChecklistDetailView.swift` verbatim (comments included); only their container
type changes. Full file:

```swift
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
                } header: {
                    Text("Destination list")
                } footer: {
                    Text("The Reminders list where the new reminders will be added.")

                    if destinationUnavailable {
                        Text("Reminder lists aren't available, so a destination can't be chosen here.")
                    } else if destinationIsStale {
                        Text("The previously selected list no longer exists. Choose another list or Default (Inbox).")
                    }
                }
                Section {
                    Toggle(isOn: numberingBinding(checklistID: checklistID)) {
                        Label("Number Reminders", systemImage: "textformat.123")
                    }
                    .accessibilityIdentifier("checklistPrefixNumbersToggle")
                } footer: {
                    Text("Prefix each reminder title with its position, like \"1: Buy milk\".")
                }
                Section {
                    Picker("Scaling", selection: scalingModeBinding(checklistID: checklistID)) {
                        Text("Fixed").tag(ScalingMode.fixed)
                        Text("Prompt").tag(ScalingMode.prompt)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("checklistScalingModePicker")
                    if store.checklist(id: checklistID)?.scaling.isPrompt != true {
                        scalingField(checklistID: checklistID)
                    }
                } header: {
                    Text("Scaling")
                } footer: {
                    Text("Scaling multiplies any integer in double brackets — e.g. ((2)) becomes 6 at Scaling 3. The brackets are removed.")
                }
                Section {
                    Toggle(isOn: showOnWatchBinding(checklistID: checklistID)) {
                        Label("Show on watch", systemImage: "applewatch")
                    }
                    .accessibilityIdentifier("checklistShowsOnWatchToggle")
                } footer: {
                    Text("Hidden checklists stay on your iPhone but are not shown on the Apple Watch.")
                }
            }
            .navigationTitle("Checklist Options")
            .toolbarTitleDisplayMode(.inline)
            .settingsSubscreenLayout()
            .onAppear { Task { await loadReminderLists() } }
        } else {
            // Deleted elsewhere (e.g. an iCloud merge) while this screen was on
            // the stack: mirror `ChecklistDetailView`'s placeholder rather than
            // binding a form to a missing checklist.
            ContentUnavailableView("Checklist not found", systemImage: "trash")
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
```

#### 2. Push link on the edit screen
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

Immediately after the existing `Section("Checklist name") { ... }` block
(`:50-54`) and before the Destination `Section` (`:55`), add its own section so
the options screen is one row under the name:

```swift
                    Section {
                        NavigationLink {
                            ChecklistOptionsView(checklistID: checklistID)
                        } label: {
                            Label("Checklist Options", systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("checklistOptionsLink")
                    }
```

#### 3. Localized key
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify

Insert after the `"Checklist not found"` entry (ends `:1642`) and before
`"Choose between system, light, and dark mode."` (`:1644`):

```json
    "Checklist Options" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Checklist Options"
          }
        },
        "de" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Checklisten-Optionen"
          }
        },
        "es" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Opciones de la lista"
          }
        },
        "fr" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "Options de la liste"
          }
        },
        "ja" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "チェックリストのオプション"
          }
        },
        "zh-Hans" : {
          "stringUnit" : {
            "state" : "translated",
            "value" : "清单选项"
          }
        }
      }
    },
```

#### 4. Localization fixture
**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify

In the `"App"` entry of `requiredKeys`, add `"Checklist Options"` in the
alphabetical gap after `"Checklist not found"` and before
`"CheckStitch couldn't ask for a scaling number. ..."` (`:35-36`), i.e.:

```swift
            "Checklist name",
            "Checklist not found",
            "Checklist Options",
            "CheckStitch couldn't ask for a scaling number. Run the checklist in the app, or pass a Multiple value.",
```

#### 5. Options-screen tests
**File**: `CheckStitchTests/ChecklistOptionsViewTests.swift`
**Action**: create

`@MainActor` Swift Testing suite mirroring `ViewRenderTests`'
`ImageRenderer` oracle (`makeIsolatedDefaults()` fixture, no live scene):

```swift
@testable import CheckStitch
import CheckStitchCore
import SwiftUI
import Testing

/// Render and construction coverage for the pushed Checklist Options screen.
/// `String(describing:)` cannot see body identifiers, so `ImageRenderer` is the
/// body oracle, exactly as `ViewRenderTests` uses it.
@MainActor
struct ChecklistOptionsViewTests {
    /// Happy path: the screen renders for an existing checklist against an
    /// injected store.
    @Test
    func optionsViewRendersForAnExistingChecklist() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)
        let checklist = store.create(name: "Groceries")

        let view = ChecklistOptionsView(checklistID: checklist.id).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }

    /// Sad path: a checklist deleted elsewhere (e.g. an iCloud merge) renders
    /// the not-found placeholder instead of a form bound to a missing value.
    @Test
    func optionsViewRendersNotFoundForAMissingChecklist() {
        let defaults = makeIsolatedDefaults()
        let store = ChecklistStore(defaults: defaults, textEditDelay: nil)

        let view = ChecklistOptionsView(checklistID: UUID()).environment(store)
        #if os(macOS)
        #expect(ImageRenderer(content: view).nsImage != nil)
        #else
        #expect(ImageRenderer(content: view).uiImage != nil)
        #endif
    }

    /// Carries the store seam plus the Destination state it moved off the edit
    /// screen (the destination-picker note and list snapshot live here now).
    @Test
    func optionsViewCarriesItsMovedStateSeams() {
        let described = String(describing: ChecklistOptionsView(checklistID: UUID()))
        #expect(described.contains("_store"))
        #expect(described.contains("checklistID"))
        #expect(described.contains("listsSnapshot"))
        #expect(described.contains("destinationUnavailable"))
    }
}
```

### Verification

#### Automated
- [x] `scripts/l10n-check.sh` passes (new key present in all 6 languages, no
      canary identity)
- [x] `make build` succeeds (new file compiles; warnings-as-errors clean)
- [x] `make test-unit` passes (`ChecklistOptionsViewTests` green, existing
      `LocalizationTests` / `ViewRenderTests` / `ChecklistDetailViewTests` green)

#### Manual
- [ ] `make run`: open a checklist, tap **Checklist Options** — the five
      controls appear, each with its existing behaviour, and the back button
      returns to the edit screen

---

## Phase 2: Remove the five controls and their helpers from the edit screen

Complete the relocation by deleting the moved sections and now-dead private
state/bindings from `ChecklistDetailView`. Behaviour is unchanged from Phase 1
because the controls already live on the options screen.

### Changes

#### 1. Delete moved state, helpers and sections
**File**: `CheckStitch/ChecklistDetailView.swift`
**Action**: modify

- Delete the file-scope `private enum ScalingMode` (`:5-7`).
- Delete `@State private var listsSnapshot` (`:44-45`) and
  `@State private var destinationUnavailable` (`:47-48`) with their doc
  comments.
- Delete the five `Section`s — Destination (`:55-73`), Number Reminders
  (`:74-85`), Scaling (`:86-100`), Show on watch (`:101-109`) — leaving the
  "Checklist name" section, the new Checklist Options link section, and the
  `Section("Items")`.
- In `.onAppear` (`:216-221`) delete the now-dead list load, leaving:

```swift
                .onAppear {
                    guard !didLoadDraft else { return }
                    draftName = checklist.name
                    didLoadDraft = true
                }
```

- Delete the now-unreferenced private helpers: `loadReminderLists()`
  (`:284-296`), `destinationIsStale` (`:302-310`), `numberingBinding`
  (`:316-321`), `scalingModeBinding` (`:328-340`), `multipleBinding`
  (`:342-347`), `scalingField` (`:355-378`), `showOnWatchBinding` (`:382-387`),
  `destinationBinding` (`:392-406`) — all now live on `ChecklistOptionsView`.

Confirm no dangling references after deletion:

```bash
rg -n 'ScalingMode|listsSnapshot|destinationUnavailable|loadReminderLists|destinationIsStale|scalingField|numberingBinding|multipleBinding|showOnWatchBinding|destinationBinding|scalingModeBinding' CheckStitch/ChecklistDetailView.swift
# expect: no matches
```

### Verification

#### Automated
- [x] `make build` succeeds with **zero** warnings (`rg` check above returns
      no matches, so no unused-private-helper/dead-code warnings)
- [x] `make test-unit` passes — the existing 28 `ChecklistDetailViewTests`
      render and store-mutator assertions stay green (none pin the moved
      controls or state slots); `ChecklistOptionsViewTests` stay green
- [x] `bash scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] `make run`: the edit screen shows only the name field, the **Checklist
      Options** row and the Items list — none of the five moved controls
- [ ] Change Destination / Number Reminders / Scaling / Factor / Show on watch
      on the options screen, go back, reopen — the values persisted through
      `ChecklistStore`

---

## Notes / risks

- The `"Prefix each reminder title with its position, like \"1: Buy milk\"."`
  footer is a raw literal not present in the catalog or `requiredKeys`
  (pre-existing; it moves verbatim). Not in scope — do not add it here.
- The options screen uses the settings-subscreen layout (`Form` +
  `settingsSubscreenLayout()`), so on macOS it is not capped to the edit form's
  centred column. This matches the named precedent
  (`ArchivedChecklistsView.swift:84-86`) and is intentional.
- `ChecklistOptionsView` carries its own `loadReminderLists()`; on iOS the
  Reminders access request is already granted by the edit screen's prior load,
  so the options screen degrades to the default-only row plus note otherwise.
