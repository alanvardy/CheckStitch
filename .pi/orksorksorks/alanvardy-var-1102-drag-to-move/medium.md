# Task

Add a drag-to-move interface to the main checklist list (the `ContentView.swift`
`checklistList` screen, shared by iOS and macOS) so the user can reorder
checklists and folders by dragging instead of (or alongside) the current
up/down nudge buttons.

Two capabilities are requested:
1. **Reorder folders** — drag a folder header to change its position in the list.
2. **Reorder checklists** — drag a checklist row to reorder it within its own
   folder (and within the loose group). Moving a checklist *between* folders or
   into/out of the loose group is **optional / "nice to have"** — handle it only
   if it drops out cleanly from the same drag plumbing; otherwise keep the
   existing "move to folder" context-menu action.

The list is **not** a SwiftUI `List` — it is a custom `LazyVStack` inside a
`ScrollView` (see `ContentView.swift:checklistList`), so drag-and-drop must be
built with `.onDrag`/`.onDrop` (+ a `DropDelegate`), not `.onMove`. Reordering a
row inside a folder must map the folder's *filtered* member index onto an index
in the store's *global* `checklists` array, since member order within a folder
is derived from global array order.

Persistence and ordering already exist and must be reused, not rebuilt:
- Folder order **is** the persisted array order; `store.moveFolders(from:to:)`
  reorders local-first and stamps no revision. `store.moveChecklists(from:to:)`
  is the same for checklists.
- Checklist folder membership is `Checklist.folderID`; `store.moveChecklist(id:toFolder:)`
  already files/un-files a checklist (bumps coarse revision for LWW).
- `listVM.moveFolder(id:up:)` / `listVM.moveChecklist(id:up:)` are the existing
  up/down nudges this replaces/supplements.

Do not change the data model, codec version, or sync contract — no migration.

## Why MEDIUM

MULTI_MODULE + BROAD_TEST_SURFACE with M1/M2 holding. The change spans the
ContentView list UI, new reorder/position methods in `ChecklistStore` and
`ChecklistListViewModel`, and tests — but the ordering approach (persisted array
order, `folderID`, existing `move*` methods) and the SwiftUI drag/drop technique
are already known, so no research or design sign-off is needed, and there is no
schema/migration or new integration.

## Key files

- `CheckStitch/ContentView.swift` — `checklistList`, `folderSection(for:)`,
  `checklistRow(for:)`, the folder/checklist context menus and current up/down
  buttons (the drag interface replaces/supplements these).
- `CheckStitch/ChecklistListViewModel.swift` — `moveChecklist(id:toFolder:)`,
  `moveFolder(id:up:)`, `moveChecklist(id:up:)`, `checklists(in:)`; add
  drag-target methods that map filtered/section indices to global store indices.
- `CheckStitch/ChecklistStore.swift` — `moveChecklists(from:to:)` (≈L457),
  `moveChecklists`/`moveChecklist(id:toFolder:)` (≈L483), `moveFolders(from:to:)`
  (≈L531). May need a method that reorders within a folder's members, or moves a
  checklist into a folder at a position.
- `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` —
  `ChecklistGrouping.sections` / `isLoose` (read-only ordering helpers) —
  likely untouched.
- Tests: `CheckStitchTests/ChecklistStoreTests.swift`,
  `CheckStitchTests/ChecklistListViewModelTests.swift` (new reorder/position
  logic, happy + boundary paths); UI smoke in `CheckStitchUITests/`.
