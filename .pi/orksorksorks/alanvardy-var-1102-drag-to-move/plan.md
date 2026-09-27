# Implementation Plan

## Overview

Add drag-to-reorder to the shared iOS/macOS `ContentView` checklist list (a
custom `LazyVStack`, not a SwiftUI `List`), as two tracer slices over the
already-persisted array order: (1) drag a checklist row to reorder it within
its own folder / within the loose group; (2) drag a folder header to reorder
folders. All index mapping lives in `ChecklistListViewModel` (unit-testable);
the store's existing `moveChecklists(from:to:)` / `moveFolders(from:to:)` do
the persistence. The edit-mode chevron nudges and the "Move to Folder" context
menu stay.

Scope decisions baked in (from `medium.md`):
- **Cross-folder checklist moves are out of scope.** Dragging a row onto another
  section is a no-op; filing a checklist into a folder stays with the existing
  "Move to Folder" menu (`moveChecklist(id:toFolder:)`), which owns the LWW
  revision bump.
- **Drag is enabled in edit mode only**, matching the existing reorder chevrons.
  Normal mode keeps the row a plain `NavigationLink` tap target. Flipping this
  later is a one-line change to the `isEditing` conditions below.
- No data-model, codec, revision or sync change; no new dependency.

Recon correction: the view model and store live in the app target
(`CheckStitch/ChecklistListViewModel.swift`, `CheckStitch/ChecklistStore.swift`),
not `CheckStitchCore/` as the AGENTS.md layout section claims. Only
`ChecklistGrouping` lives in the core package. `ChecklistStore` needs **no**
change — `moveChecklists(from:to:)` and `moveFolders(from:to:)` already do the
reorder + persist, with the `moved` index arithmetic (`ChecklistStore.swift:424`).

Swift 6 note: the app target sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
and the SDK's `DropDelegate` is `@MainActor` (`@preconcurrency`), so the
delegate below can read `@State` bindings and call the `@MainActor` view model
directly — no `nonisolated`/`assumeIsolated` workaround needed.

---

## Phase 1: Checklist drag-reorder (walking skeleton)

Thinnest end-to-end path: in edit mode, drag a checklist row over another row in
the **same section**; the dragged row takes the target's slot and the new order
persists. One row builder serves both loose rows and folder members, so this
phase covers "reorder within its own folder" and "reorder within loose" in one
slice.

### Changes

#### 1. View model drag mapping

**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: modify

Add after `moveChecklist(id:up:)` (current end of file, ≈L86):

```swift
/// The section a checklist renders in: its folder id when that folder is
/// known, otherwise nil (the loose group). Mirrors `checklists(in:)`/`isLoose`
/// so a skewed (unknown) `folderID` gates as loose, exactly as it renders.
private func sectionID(for checklist: Checklist) -> UUID? {
    guard let folderID = checklist.folderID,
          store.folders.contains(where: { $0.id == folderID }) else { return nil }
    return folderID
}

/// Maps a checklist drag onto the store's global `checklists` array. `targetID`
/// is the row the drag entered: the dragged checklist takes that row's slot in
/// its section, so a downward drag lands after the target and an upward drag
/// before it. Cross-section drags, self-drops and unknown ids are silent
/// no-ops — cross-folder filing stays with `moveChecklist(id:toFolder:)`.
func moveChecklist(id: UUID, onto targetID: UUID) {
    guard id != targetID else { return }
    guard let from = store.checklists.firstIndex(where: { $0.id == id }),
          let to = store.checklists.firstIndex(where: { $0.id == targetID }) else { return }
    guard sectionID(for: store.checklists[from]) == sectionID(for: store.checklists[to]) else { return }
    store.moveChecklists(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
}
```

The `from < to ? to + 1 : to` destination is the `moved` arithmetic
(`ChecklistStore.swift:424`): remove-then-reinsert with the target's slot
displaced, generalized from the nudge's `index + 2` for one step down.

#### 2. Drag state + reusable drop delegate

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add next to the existing `@State` properties (≈L28, beside `isEditing`):

```swift
/// The checklist currently being dragged for reorder; nil when no drag.
@State private var draggingChecklistID: UUID?
```

Add file-private next to `struct ContentView`:

```swift
/// Live-reorder DropDelegate for one row/header in the width-capped card.
/// `dropEntered` moves the dragged item into the target's slot through the view
/// model, so the section→global index mapping stays unit-tested. A nil
/// `draggingID` (no drag of this kind in flight) rejects the drop, so a
/// checklist drag cannot land on a folder header and vice versa.
private struct ReorderDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggingID: UUID?
    let move: (UUID, UUID) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        draggingID == nil ? nil : DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else { return }
        withAnimation { move(draggingID, targetID) }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}
```

#### 3. Wire the hooks into `checklistRow`

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

`checklistRow(for:)` (≈L493) currently ends with the padded `HStack`. Make it
`@ViewBuilder`, bind the row to a local, and apply the hooks only in edit mode
(content unchanged):

```swift
@ViewBuilder
private func checklistRow(for checklist: Checklist) -> some View {
    let row = HStack(spacing: 12) {
        // ... existing remove / name / folder-menu / chevrons / navigation
        //     and reminders-button content, byte-for-byte unchanged ...
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)

    if isEditing {
        row
            .onDrag {
                draggingChecklistID = checklist.id
                return NSItemProvider(object: checklist.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDropDelegate(
                targetID: checklist.id,
                draggingID: $draggingChecklistID,
                move: { listVM.moveChecklist(id: $0, onto: $1) }))
    } else {
        row
    }
}
```

`UniformTypeIdentifiers` is already imported in this file (`.text`).

#### 4. Tests

**File**: `CheckStitchTests/ChecklistListViewModelTests.swift`
**Action**: modify

Append a drag section (Swift Testing, `@MainActor struct`, `#expect`; helpers
`makeViewModel()`, `makeIsolatedDefaults()` already exist):

```swift
// MARK: Drag to move

@Test
func dragChecklistDownOntoRowTakesItsSlot() {
    let viewModel = makeViewModel()
    let first = viewModel.createChecklist()
    let second = viewModel.createChecklist()
    let third = viewModel.createChecklist()
    viewModel.moveChecklist(id: first, onto: third)
    #expect(viewModel.checklists.map(\.id) == [second, third, first])
}

@Test
func dragChecklistUpOntoRowTakesItsSlot() {
    let viewModel = makeViewModel()
    let first = viewModel.createChecklist()
    let second = viewModel.createChecklist()
    let third = viewModel.createChecklist()
    viewModel.moveChecklist(id: third, onto: first)
    #expect(viewModel.checklists.map(\.id) == [third, first, second])
}

@Test
func dragChecklistOntoItselfIsANoOp() {
    let viewModel = makeViewModel()
    let first = viewModel.createChecklist()
    let second = viewModel.createChecklist()
    viewModel.moveChecklist(id: first, onto: first)
    #expect(viewModel.checklists.map(\.id) == [first, second])
}

@Test
func dragChecklistOntoAnotherSectionsRowIsANoOp() {
    let viewModel = makeViewModel()
    let folder = viewModel.createFolder(name: "Work")
    let filed = viewModel.createChecklist()
    let loose = viewModel.createChecklist()
    viewModel.moveChecklist(id: filed, toFolder: folder)

    viewModel.moveChecklist(id: filed, onto: loose)

    let f = viewModel.folders.first { $0.id == folder }!
    #expect(viewModel.checklists(in: f).map(\.id) == [filed])
    #expect(viewModel.checklists(in: nil).map(\.id) == [loose])
}

@Test
func dragChecklistWithinFolderReordersAroundOtherFoldersMembers() {
    // Global order [c1(fA), x(fB), c2(fA)]: the mapping must skip x entirely.
    let viewModel = makeViewModel()
    let folderA = viewModel.createFolder(name: "Work")
    let folderB = viewModel.createFolder(name: "Personal")
    let c1 = viewModel.createChecklist()
    let x = viewModel.createChecklist()
    let c2 = viewModel.createChecklist()
    viewModel.moveChecklist(id: c1, toFolder: folderA)
    viewModel.moveChecklist(id: x, toFolder: folderB)
    viewModel.moveChecklist(id: c2, toFolder: folderA)

    viewModel.moveChecklist(id: c1, onto: c2)

    let a = viewModel.folders.first { $0.id == folderA }!
    let b = viewModel.folders.first { $0.id == folderB }!
    #expect(viewModel.checklists(in: a).map(\.id) == [c2, c1])
    #expect(viewModel.checklists(in: b).map(\.id) == [x])
}

@Test
func dragChecklistOrderPersistsAndReloads() {
    let defaults = makeIsolatedDefaults()
    let first = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
    let a = first.createChecklist()
    let b = first.createChecklist()
    first.moveChecklist(id: b, onto: a)

    let reloaded = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
    #expect(reloaded.checklists.map(\.id) == [b, a])
}
```

#### 5. Accessibility identifiers (drag affordances)

Leave the existing `moveChecklistUp-<uuid>` / `moveChecklistDown-<uuid>` ids
untouched (the chevrons stay). No new identifier is required — the UI smoke does
not drive drags. Do **not** add a drag-only identifier that no test uses.

### Verification

#### Automated
- [x] `make test-unit` passes (new drag tests + existing suite)
- [x] `make build` passes (shared `ContentView` compiles for the iOS simulator)
- [x] `make build-mac` passes (macOS slice of the shared view)

#### Manual
- [ ] `make run`; tap Edit; long-press a checklist row and drag it over another
      row in the same folder — the dragged row takes that slot and the order
      survives relaunch.
- [ ] In edit mode, drag a loose checklist over a folder member (and vice
      versa) — both sections are unchanged (cross-section no-op).
- [ ] In edit mode, drag the first loose row past the last loose row — it lands
      last (boundary).
- [ ] Leave edit mode: tapping a row still pushes the detail screen, and the
      remove/folder/chevron controls are gone.

---

## Phase 2: Folder drag-reorder

Adds the second capability: drag a folder header to change its position among
folders. Reuses `ReorderDropDelegate` from Phase 1 (contract: `targetID`,
`@Binding draggingID`, `move` closure). Depends on Phase 1's delegate, not its
internals.

### Changes

#### 1. View model drag mapping

**File**: `CheckStitch/ChecklistListViewModel.swift`
**Action**: modify

Add after `moveFolder(id:up:)` (or at the end, next to the Phase 1 method):

```swift
/// Maps a folder drag onto the store's `folders` array. Same take-the-slot
/// semantics as `moveChecklist(id:onto:)`; self-drops and unknown ids are
/// silent no-ops. Folder order is the persisted array order, so no revision
/// is stamped (mirrors `moveFolders`/`moveFolder(id:up:)`).
func moveFolder(id: UUID, onto targetID: UUID) {
    guard id != targetID else { return }
    guard let from = store.folders.firstIndex(where: { $0.id == id }),
          let to = store.folders.firstIndex(where: { $0.id == targetID }) else { return }
    store.moveFolders(from: IndexSet(integer: from), to: from < to ? to + 1 : to)
}
```

#### 2. Drag state + hooks on the folder header

**File**: `CheckStitch/ContentView.swift`
**Action**: modify

Add beside `draggingChecklistID`:

```swift
/// The folder currently being dragged for reorder; nil when no drag.
@State private var draggingFolderID: UUID?
```

`folderHeader(for:isCollapsed:)` (≈L584, already `@ViewBuilder`) — bind the
existing header `HStack` to a local and apply the hooks in edit mode (content
unchanged):

```swift
@ViewBuilder
private func folderHeader(for folder: Folder, isCollapsed: Bool) -> some View {
    let header = HStack(spacing: 8) {
        // ... existing disclosure button, folder glyph, name, edit controls ...
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)

    if isEditing {
        header
            .onDrag {
                draggingFolderID = folder.id
                return NSItemProvider(object: folder.id.uuidString as NSString)
            }
            .onDrop(of: [.text], delegate: ReorderDropDelegate(
                targetID: folder.id,
                draggingID: $draggingFolderID,
                move: { listVM.moveFolder(id: $0, onto: $1) }))
    } else {
        header
    }
}
```

The two drag kinds are distinguished by their `@State` binding: a checklist
drag leaves `draggingFolderID` nil (folder delegate rejects it), and a folder
drag leaves `draggingChecklistID` nil (checklist delegate rejects it). Folder
headers are all rendered before the loose group, so folder indices map directly
onto `store.folders`.

#### 3. Tests

**File**: `CheckStitchTests/ChecklistListViewModelTests.swift`
**Action**: modify

```swift
@Test
func dragFolderDownOntoFolderTakesItsSlot() {
    let viewModel = makeViewModel()
    let first = viewModel.createFolder(name: "Work")
    let second = viewModel.createFolder(name: "Personal")
    let third = viewModel.createFolder(name: "Errands")
    viewModel.moveFolder(id: first, onto: third)
    #expect(viewModel.folders.map(\.id) == [second, third, first])
}

@Test
func dragFolderUpOntoFolderTakesItsSlot() {
    let viewModel = makeViewModel()
    let first = viewModel.createFolder(name: "Work")
    let second = viewModel.createFolder(name: "Personal")
    let third = viewModel.createFolder(name: "Errands")
    viewModel.moveFolder(id: third, onto: first)
    #expect(viewModel.folders.map(\.id) == [third, first, second])
}

@Test
func dragFolderOntoItselfIsANoOp() {
    let viewModel = makeViewModel()
    let first = viewModel.createFolder(name: "Work")
    let second = viewModel.createFolder(name: "Personal")
    viewModel.moveFolder(id: first, onto: first)
    #expect(viewModel.folders.map(\.id) == [first, second])
}

@Test
func dragFolderOntoUnknownIDIsANoOp() {
    let viewModel = makeViewModel()
    let only = viewModel.createFolder(name: "Work")
    viewModel.moveFolder(id: only, onto: UUID())
    #expect(viewModel.folders.map(\.id) == [only])
}

@Test
func dragFolderOrderPersistsAndReloads() {
    let defaults = makeIsolatedDefaults()
    let first = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
    let a = first.createFolder(name: "Work")
    let b = first.createFolder(name: "Personal")
    first.moveFolder(id: b, onto: a)

    let reloaded = ChecklistListViewModel(store: ChecklistStore(defaults: defaults, textEditDelay: nil))
    #expect(reloaded.folders.map(\.id) == [b, a])
}
```

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `make build` passes (iOS simulator)
- [x] `make build-mac` passes (macOS)
- [x] `bash scripts/test.sh` prints `gate: ok` (run once, after this phase;
      it covers `make build`, `make test`, `make build-mac`, `make watch-build`,
      `scripts/tests/run.sh`, `shellcheck`)

#### Manual
- [ ] `make run`; tap Edit; drag a folder header over another folder header —
      the folder takes that slot and the order survives relaunch.
- [ ] Drag a collapsed folder's header — it reorders without expanding.
- [ ] Drag a checklist row over a folder header (and a folder header over a
      checklist row) — no reorder occurs in either direction.
- [ ] The chevron up/down nudges and the "Move to Folder" menu still work.

---

## Notes for the implementer

- **Do not change** `ChecklistStore`, the codec version, `Checklist`/
  `Folder`, `ChecklistGrouping`, or any `revision`/`modifiedAt` stamping.
  Reorder stays local-first with no revision bump; cross-folder filing keeps
  the existing `moveChecklist(id:toFolder:)` LWW path.
- Only these files change: `CheckStitch/ChecklistListViewModel.swift`,
  `CheckStitch/ContentView.swift`,
  `CheckStitchTests/ChecklistListViewModelTests.swift`.
- New files under `CheckStitch/` need no `project.pbxproj` edit (the project
  uses `PBXFileSystemSynchronizedRootGroup`), but this plan adds none.
- No new user-facing strings, so `Localizable.xcstrings` and
  `scripts/l10n-check.sh` are untouched.
- Gate legs compile with warnings-as-errors; keep the delegate free of
  unused-parameter and actor-isolation warnings.