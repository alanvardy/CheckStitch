# Implementation Plan

## Overview

Add an **Edit mode to the main checklist screen** so checklists can be reordered
and removed, mirroring the items-edit experience on the detail screen. Because
the main screen is a custom plated `LazyVStack` (not a `Form`/`List`), SwiftUI
renders no drag UI there and there is no `EditMode` precedent in the repo, so
edit mode is an explicit `@State isEditing` flag driving **per-row controls**: a
leading red minus that opens the existing-style `confirmationDialog`, and
trailing up/down move buttons. The plated card rendering is untouched, and the
persisted format does not change — the top-level `[Checklist]` array order
*is* the stored order and `ChecklistMerge` is already local-wins for it.

### Invariants / not in scope

- **No schema change, no codec version bump, no order clock.** `ChecklistEnvelope`
  stays at v4; `ChecklistMerge.swift` is not edited. A reorder is carried to
  other devices by the existing `save()` push only, exactly like the local-wins
  array order it already ships.
- Watch target (`CheckStitchWatch`) is untouched — it renders a read-only mirror.
- No new dependencies, no new files, no refactors of adjacent code.
- Existing UI-smoke identifiers (`createChecklistButton`, `settingsButton`,
  `createRemindersButton`, `emptyStateCreateButton`) keep rendering in the default
  (non-editing) state, so `CheckStitchUITests` keeps passing unchanged.
- New strings are user-facing and must all be registered: **"Edit"**, **"Move up"**,
  **"Move down"**. ("Remove", "Remove Checklist", "Cancel", "Done",
  "This removes the checklist and all its items." are already registered and
  already listed in `LocalizationFixtures.requiredKeys`.)

### Verified recon anchors

- `CheckStitch/ChecklistStore.swift:341-356` — private `static func moved<T>(_ array: [T], from offsets: IndexSet, to destination: Int) -> [T]?` returns `nil` for empty offsets, out-of-range offsets, or `destination` outside `0...array.count`. Reused as-is.
- `CheckStitch/ChecklistStore.swift:370-378` — `delete(id:)` is the whole-checklist tombstone precedent: `ChecklistTombstone(checklistID: id, itemID: nil, deletedAt: now(), revision: removed.revision + 1)`.
- `CheckStitch/ChecklistStore.swift:325-339` — `removeItems(from:at:)` is the batch precedent: iterate offsets descending, append per-removal tombstones, **one** `save()`.
- `CheckStitch/ChecklistStore.swift:23` — `private(set) var checklists: [Checklist]`; `:28` `private(set) var tombstones`; `:31` `@ObservationIgnored var onChange: (() -> Void)?`; `:427` `private func save()` fires `onChange?()` unless `isApplyingRemote`. `:118` `checklist(id:)`, `:134` `create(name: String = "New checklist")`.
- `CheckStitch/ChecklistMerge.swift:62-71` — `var result = local`, remote-only ids `append`; local top-level order always wins.
- `CheckStitch/ContentView.swift:282-318` — `GeometryReader > ScrollView > LazyVStack` with `ForEach(store.checklists)` (element-based, **no indices**), plate `.background`/`.overlay` on the `LazyVStack`, `.padding(.top, CardPlate.checklistTopMargin)` under `#if os(iOS)` else `16`.
- `CheckStitch/ContentView.swift:320-326` — `checklistRow(for:)`: `NavigationLink(checklist.name, value: checklist.id)` + `createRemindersButton(for:)`.
- `CheckStitch/ContentView.swift:139-155` — iOS chrome overlays: create `.topLeading`, settings `.topTrailing`, both `.padding(.top, 8)` / `.padding(.leading|trailing, 12)`, guarded by `path.isEmpty`.
- `CheckStitch/ContentView.swift:50-67` — macOS `.toolbar` with create (`createButtonPlacement`) + settings (`.primaryAction`).
- `CheckStitch/ChecklistDetailView.swift:64-79` — `.onDelete`/`.onMove` on the `ForEach`; `:110-114` `EditButton()` is `#if os(iOS)` only; `:98-104` `removeChecklistButton`; confirmation two-step gate at `:156-167`.
- `CheckStitchTests/ChecklistStoreTests.swift` — **XCTest** (`@MainActor final class`, `XCTAssertEqual`/`XCTUnwrap`), fixtures `makeDefaults()` `:10-16`, `makeStore(defaults:)` `:21-23`, `makeItemStore(defaults:titles:)` `:27-35`, `store.create(name:)` (default `"New checklist"`), `onChange` counter precedent at `:623`.
- `CheckStitchTests/LocalizationFixtures.swift:12+` — `requiredKeys: [(catalog: String, keys: [String])]`, App list is alphabetical; enforced by `LocalizationTests` `catalogsHaveAllSixLanguages` / `everyRequiredKeyIsPresent`, plus the `nonEnglishValuesDifferFromEnglish` canary.
- `CheckStitch/Localizable.xcstrings` — per key: `{ "extractionState": "manual", "localizations": { "<lang>": { "stringUnit": { "state": "translated", "value": "..." } } } }`; six languages `en, de, es, fr, ja, zh-Hans`. Existing style reference: `"Done"` → de `Fertig`, es `Listo`, fr `Terminé`, ja `完了`.
- Gate: `make test-unit` (fast, macOS) → `make build` → `make build-mac` (compiles the `#if os(macOS)` branch) → `make test-ui` (smoke) → full `./scripts/test.sh` once at the end.

---

## Phase 1: Edit mode + remove checklists (walking skeleton)

Thinnest end-to-end path: a user taps **Edit** on the main screen, taps the red
minus on a row, confirms, and the checklist disappears and stays gone across a
relaunch — with a whole-checklist tombstone on disk.

Commit: `feat: add checklist edit mode with removal from the main screen`

### Changes

#### 1. Store — batch removal with whole-checklist tombstones
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify — add a new public method next to `removeItems(from:at:)`
(`:325-339`); leave `moved<T>`, `delete(id:)`, `save()` untouched.

```swift
/// Removes whole checklists, one tombstone each. Mirrors
/// `removeItems(from:at:)`: every removal is stamped in a single batch and
/// persisted once, so a multi-row removal is one save and one sync push.
/// Out-of-range offsets are skipped; an all-out-of-range or empty set is a
/// silent no-op (no tombstone, no save).
func removeChecklists(at offsets: IndexSet) {
    let removed = offsets.compactMap { checklists.indices.contains($0) ? checklists[$0] : nil }
    guard !removed.isEmpty else { return }
    for index in offsets.sorted(by: >) where checklists.indices.contains(index) {
        checklists.remove(at: index)
    }
    for checklist in removed {
        tombstones.append(ChecklistTombstone(
            checklistID: checklist.id, itemID: nil, deletedAt: now(),
            revision: checklist.revision + 1))
    }
    save()
}
```

Note: `removed` is collected in ascending offset order **before** any mutation so
tombstone order is deterministic (the codec writes the tombstone array verbatim);
the deletes then run descending, which is what keeps indices valid.

#### 2. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify — add a fixture next to `makeItemStore` (`:27-35`) and a
`// MARK: - removeChecklists` section after the `// MARK: - moveItems` section's
tombstone tests (around `:982-1030`).

```swift
/// Three named checklists — the smallest fixture that exercises batch removal.
private func makeChecklistStore(defaults: UserDefaults, names: [String]) -> ChecklistStore {
    let store = makeStore(defaults: defaults)
    for name in names { _ = store.create(name: name) }
    return store
}
```

Tests (XCTest, `@MainActor` class, `makeDefaults()` + `defer { …removePersistentDomain }`):

- `testRemoveChecklistsDeletesRowsAndLeavesTombstones` — three checklists, `removeChecklists(at: [0, 2])`; remaining names `["Hardware"]`; `tombstones.count == 2`; every tombstone `itemID == nil`; each `revision == removedChecklist.revision + 1`; `deletedAt` non-nil.
- `testRemoveChecklistsLeavesOnlyWholeChecklistTombstones` — a checklist with items is removed and produces **one** tombstone, not one per item (the `itemID == nil` path covers the items).
- `testRemoveChecklistsOutOfRangeIsNoOp` — `[7]` on three checklists: names and `tombstones` unchanged, and captured `suite.defaults.data(forKey: key)` byte-identical.
- `testRemoveChecklistsEmptyOffsetsIsNoOp` — `IndexSet()` leaves `changes == 0` on a `store.onChange = { changes += 1 }` counter (`:623` precedent).
- `testRemoveChecklistsSavesOnce` — batch of two fires `onChange` exactly once.
- `testRemoveChecklistsPersistsAcrossReload` — reload over the same defaults: one checklist remains and both tombstones survive.

#### 3. Localization — the bare "Edit"
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify — add one key, `"Edit"`, with all six languages (same shape as
`"Done"` at `:1316`): en `Edit`, de `Bearbeiten`, es `Editar`, fr `Modifier`,
ja `編集`, zh-Hans `编辑`.

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify — insert `"Edit",` into the `("App", [...])` list in
alphabetical position (between `"Duplicate Checklist"` and `"Edit checklist"`, i.e.
line 38 today).

#### 4. ContentView — edit state, toggle, per-row remove control, confirmation
**File**: `CheckStitch/ContentView.swift`
**Action**: modify.

State (next to the existing `@State` block at `:27-50`):

```swift
@State private var isEditing = false
@State private var checklistPendingRemoval: UUID?
```

Toggle view — one shared view, placed per platform (iOS has no toolbar on the
root; both chrome corners are occupied by the 52×52 create/settings plates, so
the iOS toggle lives in the scroll content as a right-aligned header row above
the plated card, sharing the card's 32pt horizontal padding):

```swift
/// Shared by the macOS toolbar and the iOS in-content header row. The bare
/// "Edit" key is new; "Done" is already registered.
private var editToggleButton: some View {
    Button(isEditing ? "Done" : "Edit") {
        withAnimation { isEditing.toggle() }
    }
    .accessibilityIdentifier("editChecklistsButton")
}
```

`checklistList` (`:282-318`) — wrap the `LazyVStack` in a `VStack(spacing: 0)`
that carries the existing `.padding(.top, …)`/`.padding(.bottom, 16)`/
`.frame(maxWidth: .infinity, alignment: .center)`, and add the iOS header row as
the *first* child (outside the plate, so the plate `.background`/`.overlay` stay
on the `LazyVStack` exactly as today):

```swift
ScrollView {
    VStack(spacing: 0) {
        #if os(iOS)
            HStack {
                Spacer()
                editToggleButton
            }
            .frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))
            .padding(.horizontal, 32)
            .padding(.bottom, 8)
        #endif
        LazyVStack(spacing: 0) { /* …unchanged… */ }
            .frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width))
            .background { /* unchanged plate */ }
            .overlay(/* unchanged stroke */)
            .padding(.horizontal, 32)
    }
    #if os(iOS)
        .padding(.top, CardPlate.checklistTopMargin)
    #else
        .padding(.top, 16)
    #endif
    .padding(.bottom, 16)
    .frame(maxWidth: .infinity, alignment: .center)
}
```

Make the iOS header legible over the background photo by giving the label a
plated treatment mirroring the chrome plates — `CardPlate.iconPlateFill(for: colorScheme)`
inside a `RoundedRectangle(cornerRadius: CardPlate.cornerRadius)` (or `.capsule`),
with `.padding(.horizontal, 14).padding(.vertical, 6)`; the implementer should
match whatever compiles cleanly rather than invent new colors.

macOS toolbar (`:50-67`) — add a third item, still suppressed in the empty state:

```swift
if !store.checklists.isEmpty {
    ToolbarItem(placement: .primaryAction) { editToggleButton }
}
```

Row (`:320-326`) — in edit mode the row stops navigating (a `NavigationLink`
would push mid-edit) and the run button is hidden, so a stray tap cannot create
reminders while editing:

```swift
private func checklistRow(for checklist: Checklist) -> some View {
    HStack(spacing: 12) {
        if isEditing {
            Button {
                checklistPendingRemoval = checklist.id
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove")
            .accessibilityIdentifier("removeChecklist-\(checklist.id.uuidString)")
        }
        if isEditing {
            Text(checklist.name)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            NavigationLink(checklist.name, value: checklist.id)
                .frame(maxWidth: .infinity, alignment: .leading)
            createRemindersButton(for: checklist.id)
        }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}
```

Helpers, next to `createReminders(for:)`:

```swift
private func removeChecklist(id: UUID) {
    guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
    store.removeChecklists(at: IndexSet(integer: index))
}
```

Confirmation — same two-step gate as `ChecklistDetailView` (`:156-167`), attached
to the root `ZStack` modifier chain beside the existing `.alert`s. All four
strings are already registered; the identifiers mirror the detail screen:

```swift
.confirmationDialog(
    "Remove Checklist",
    isPresented: Binding(get: { checklistPendingRemoval != nil },
                         set: { if !$0 { checklistPendingRemoval = nil } }),
    presenting: checklistPendingRemoval
) { id in
    Button("Remove", role: .destructive) { removeChecklist(id: id) }
        .accessibilityIdentifier("confirmRemoveChecklistButton")
    Button("Cancel", role: .cancel) { checklistPendingRemoval = nil }
        .accessibilityIdentifier("cancelRemoveChecklistButton")
} message: { _ in
    Text("This removes the checklist and all its items.")
}
```

Leave edit mode when the last checklist goes, so a later create does not open
into a stale edit state (an empty store shows `emptyState`, which has no toggle):

```swift
.onChange(of: store.checklists.isEmpty) { _, isEmpty in
    if isEmpty { isEditing = false }
}
```

### Verification
#### Automated
- [x] `make build` passes (the sim build compiles the `#if os(iOS)` header path)
- [x] `make build-mac` passes (the `#if os(macOS)` toolbar path and the shared row compile)
- [x] `make test-unit` passes — new `removeChecklists` tests, plus `LocalizationTests` `everyRequiredKeyIsPresent` and `catalogsHaveAllSixLanguages` for the new `"Edit"` key
- [x] `make test-ui` passes unchanged (`createChecklistButton`, `settingsButton`, `createRemindersButton`, `emptyStateCreateButton` all still resolve; edit mode is off at launch)

#### Manual
- [ ] `make run`, then: tapping **Edit** shows a red minus on each row, hides each row's play button, and row taps no longer push the detail screen; the label reads **Done**
- [ ] Tapping a row's minus shows the "Remove Checklist" dialog; **Cancel** keeps the checklist; **Remove** deletes it and the remaining rows keep their order
- [ ] Removing the last checklist lands on the empty state and the toggle is gone; creating a checklist afterwards does not reopen in edit mode
- [ ] Previously created reminders in the Reminders app are untouched (this feature never deletes reminders)
- [ ] On macOS (`make build-mac-signed` + run): the Edit item appears in the title bar next to create/settings and behaves identically

---

## Phase 2: Reorder checklists

Adds the move controls and the store's reorder API, on top of Phase 1's edit mode.

Commit: `feat: reorder checklists from the main screen edit mode`

### Changes

#### 1. Store — top-level reorder
**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify — add beside `moveItems(checklistID:from:to:)` (`:358-368`).

```swift
/// Reorders checklists. Unlike `moveItems` there is no per-checklist order
/// clock to stamp: the top-level array order *is* the persisted order, and
/// `ChecklistMerge` keeps local order (remote-only checklists append), so a
/// reorder is local-first by design and needs no revision bump.
/// Out-of-range offsets/destinations are silent no-ops.
func moveChecklists(from offsets: IndexSet, to destination: Int) {
    guard let reordered = Self.moved(checklists, from: offsets, to: destination) else { return }
    checklists = reordered
    save()
}
```

#### 2. Store tests
**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify — a `// MARK: - moveChecklists` section using the
`makeChecklistStore` fixture added in Phase 1. `IndexSet(integer: 0)` → `to: 2`
on `["Groceries", "Hardware", "Travel"]` yields `["Hardware", "Groceries", "Travel"]`
(the same arithmetic the item precedent asserts at `:756`).

- `testMoveChecklistsReordersWithinList` — the case above, by `\.name`.
- `testMoveChecklistsToEnd` — `0 … to: 3` yields `["Hardware", "Travel", "Groceries"]`.
- `testMoveChecklistsOutOfRangeIsNoOp` — offsets `[5]` and destination `99`: order unchanged and stored bytes identical.
- `testMoveChecklistsEmptyOffsetsIsNoOp` — `IndexSet()`, then `changes == 0` via the `onChange` counter.
- `testMoveChecklistsPreservesChecklistIdentity` — after a reorder, each checklist's `id`, `name`, `revision`, `modifiedAt`, `items` and `itemOrder` are byte-equal to before; only the array order changed (a reorder is never mistaken for a checklist edit, so it must not win an LWW round).
- `testMoveChecklistsPersistsAcrossReload` — a reload over the same defaults sees the new order.

#### 3. Localization — move labels
**File**: `CheckStitch/Localizable.xcstrings`
**Action**: modify — two keys with all six languages:
`"Move up"` (de `Nach oben`, es `Subir`, fr `Monter`, ja `上へ移動`, zh-Hans `上移`)
and `"Move down"` (de `Nach unten`, es `Bajar`, fr `Descendre`, ja `下へ移動`, zh-Hans `下移`).

**File**: `CheckStitchTests/LocalizationFixtures.swift`
**Action**: modify — insert `"Move down",` and `"Move up",` into the
alphabetical `("App", [...])` list, between
`"Made with ❤️ by a Canadian developer 🇨🇦"` and `"Name"` (lines 46-47 today).

#### 4. ContentView — move controls
**File**: `CheckStitch/ContentView.swift`
**Action**: modify — add a move-control group to the edit-mode row from Phase 1
(the trailing slot, next to where the run button is hidden), plus the helper.

```swift
@ViewBuilder
private func checklistMoveControls(for checklist: Checklist) -> some View {
    HStack(spacing: 4) {
        Button { moveChecklist(checklist.id, up: true) } label: {
            Image(systemName: "chevron.up")
        }
        .buttonStyle(.plain)
        .disabled(store.checklists.first?.id == checklist.id)
        .accessibilityLabel("Move up")
        .accessibilityIdentifier("moveChecklistUp-\(checklist.id.uuidString)")

        Button { moveChecklist(checklist.id, up: false) } label: {
            Image(systemName: "chevron.down")
        }
        .buttonStyle(.plain)
        .disabled(store.checklists.last?.id == checklist.id)
        .accessibilityLabel("Move down")
        .accessibilityIdentifier("moveChecklistDown-\(checklist.id.uuidString)")
    }
}
```

`moveChecklist` converts a nudge into the `moved` arithmetic: one row up is
`destination == index - 1`, one row down is `index + 2` (the destination is
adjusted for the removed element, exactly as `moveItems` documents at `:358-368`).

```swift
private func moveChecklist(_ id: UUID, up: Bool) {
    guard let index = store.checklists.firstIndex(where: { $0.id == id }) else { return }
    store.moveChecklists(from: IndexSet(integer: index), to: up ? index - 1 : index + 2)
}
```

Call it from the edit-mode row added in Phase 1 as the trailing element:

```swift
if isEditing { checklistMoveControls(for: checklist) }
```

### Verification
#### Automated
- [ ] `make build` passes
- [ ] `make build-mac` passes
- [ ] `make test-unit` passes — new `moveChecklists` tests plus the localization suites for `"Move up"` / `"Move down"`
- [ ] `make test-ui` passes unchanged (no row gains a move control outside edit mode)
- [ ] `bash scripts/test.sh` prints `gate: ok` (full gate, run once after both phases commit)

#### Manual
- [ ] `make run`: in edit mode each row shows chevrons; the first row's up and the last row's down are disabled/dimmed
- [ ] Tapping down on the first row swaps it with the second and the rows animate; the buttons re-disable at the new ends
- [ ] The new order survives relaunch (`make run` again) and the row that moved keeps its items and its detail screen
- [ ] Non-editing state is visually unchanged from before this ticket: plated card, floating create/settings plates, per-row play button