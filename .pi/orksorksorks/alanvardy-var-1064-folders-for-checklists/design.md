# Design Discussion

## Current State

- **One domain file, one codec.** Entities and the wire format live in
  `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`: `ChecklistItem`
  (`:8`), `Checklist` (`:145`), `ChecklistTombstone` (`:307`),
  `ChecklistEnvelope` (`:323`), `ChecklistCodec` with `currentVersion = 4`
  (`:367-368`). `classify` (`:389-422`) returns `loaded`, `migratable(from:)`,
  `unsupportedVersion`, `unreadable`.
- **Additive-field pattern works without a version bump** for optional scalars:
  every key decodes via `decodeIfPresent(...) ?? default` and is written
  unconditionally (`Checklist.swift:96-98`, `:200-201`). `Checklist` already
  carries a `String?` relationship field, `destinationListIdentifier` (`:172`).
  Closed enums are the exception (`priority`, `:113-117`).
- **`ChecklistStore` is the sole encoder/persister** (`CheckStitch/ChecklistStore.swift`):
  one `UserDefaults`/App-Group key `"checklists.v1"`, `envelope` getter
  (`:130-137`), single `save()` (`:483-495`), load switch at `:79-125`
  (`case 1` restamps, `case 2` seeds order, `default` loads v3+ verbatim).
- **Mutations are `mutate self.checklists` + one `save()`**: `create`
  (`:134-141`, `uniqueName` disambiguation), `duplicate` (`:156-171`),
  `removeChecklists(at:)` (`:390-401`, appends tombstones), `moveChecklists(from:to:)`
  (`:441-444`, local-first, **no revision bump**).
- **Merge is explicit per scalar.** `ChecklistMerge.mergedChecklists`
  (`CheckStitch/ChecklistMerge.swift:27-75`) only transfers `name`,
  `destinationListIdentifier`, `prefixesReminderNumbers`, `revision`,
  `modifiedAt` when remote wins (`:64-71`); order merges separately via
  `orderRevision`/`orderModifiedAt` (`:72-96`). No reflection.
- **UI**: `ContentView` (`CheckStitch/ContentView.swift`) — `NavigationStack(path: [UUID])`
  (`:28-58`), `@State isEditing` (`:25`), `checklistList` (`:260-305`),
  `checklistRow(for:)` branches on edit mode (`:306-338`), `checklistMoveControls`
  (`:340-365`), staged removal via `checklistPendingRemoval` + dialog
  (`:271-297`), iOS edit toggle in-content (`:264-285`), macOS toolbar variant
  (`:39-54`). No context menus, swipe actions, or per-row gestures anywhere.
- **View model**: `ChecklistListViewModel` (`CheckStitch/ChecklistListViewModel.swift`)
  is a thin `@MainActor @Observable` forwarder over the store.
- **Watch**: `WatchChecklistListView.swift` renders a flat
  `List(viewModel.checklists)` with `NavigationLink` into `WatchChecklistDetailView`,
  fed by `WatchChecklistViewModel`. No grouping surface today.

## Desired End State

The main checklist screen is partitioned into **folders** (named groups) plus a
**loose** group for checklists that belong to no folder. Users can create, rename,
reorder and delete folders (all folder actions revealed only in edit mode),
and can move a checklist into a folder, to another folder, or back to loose.
A folder's contents are the checklists whose `folderID` matches, rendered in the
existing persisted top-level order. The watch list shows the same folders as
`Section`s.

Verification:
- `make test-unit` covers: model codec v4→v5 migration, additive `folderID`
  decode default, store folder CRUD/reorder, membership move, folder delete
  orphaning its checklists, merge of folders + folder tombstones, and the VM
  surface.
- `make build` + `make test-ui` smoke still pass; `bash scripts/test.sh` prints
  `gate: ok` including the watch compile leg.
- Localization: every new key in all six languages, present in
  `LocalizationFixtures.requiredKeys` for App **and** Watch catalogs.
- On a real device/build: the installed app shows folder sections and moves work
  (sync/UI tickets cannot close on static evidence).

## Patterns to Follow

- **Model + codec in the one file**: define `Folder` and `FolderTombstone` in
  `Checklist.swift` beside `ChecklistTombstone` (`:307`) so the "one model file"
  invariant (`research.md` cross-cutting) holds.
- **Additive key decoding**: `folderID: UUID?` decodes via
  `decodeIfPresent(UUID.self, forKey: .folderID)`, exactly as
  `destinationListIdentifier` does (`Checklist.swift:172`); encode writes the
  key unconditionally (use `encodeIfPresent`/`encodeNil` consistent with the
  existing `String?` handling).
- **Envelope-key defaulting**: `folders`/`folderTombstones` decode with
  `decodeIfPresent(...) ?? []`, same shape as `tombstones`
  (`Checklist.swift:341-346`).
- **Version-gated protection**: insert new cases above the existing `default` in
  `ChecklistStore.load` (`:76-90`) only if a folder-specific restamp is needed;
  v5 is otherwise verbatim. A v4 build reading a v5 payload must hit
  `.unsupportedVersion` and set `canOverwriteStoredPayload = false`.
- **Explicit merge lines**: add folder fields to
  `ChecklistMerge.mergedChecklists` (`ChecklistMerge.swift:64-71`) by name; do
  not invent reflection.
- **Single `save()` batches**: all folder mutations follow `create`/`moveChecklists`
  (`ChecklistStore.swift:134-141`, `:441-444`) — mutate, then one `save()`.
- **Row controls live under `isEditing`**: extend the existing branch in
  `checklistRow(for:)` (`ContentView.swift:306-338`) rather than adding
  swipe/context gestures, which the codebase has deliberately avoided.
- **Test shapes**: XCTest + fresh isolated `UserDefaults` + `textEditDelay: nil`
  for store (`ChecklistStoreTests.swift`), Swift Testing `@MainActor struct` for
  VM (`CheckListListViewModelTests.swift`).
- **Bad patterns to avoid**: an enum for folder identity (closed enums need a
  version bump and hard-fail on unknown values — `Checklist.swift:113-117`);
  a second persistence key/store; duplicating order state in both `Folder` and
  the checklist array.

## Design Decisions

1. **Folders ride in the existing envelope, `currentVersion` 4 → 5** — one key,
   one transport, one merge host; the bump is what makes a v4 build refuse to
   overwrite a v5 payload written by a newer app sharing the App Group.
2. **`folderID: UUID?` on `Checklist`; ordering is the existing top-level array
   order** — reuses the local-first, no-revision-bump reorder semantics
   (`ChecklistStore.swift:441-444`) and keeps membership a one-field change. The
   `folders` array itself carries folder order, also reordered local-first.
3. **Deleting a folder orphans its checklists** — set affected checklists'
   `folderID = nil` and append a `FolderTombstone`; never write checklist
   tombstones as a side effect. No destructive confirm needed beyond the
   existing staged-dialog shape.
4. **Main screen renders folder sections inline** — header row + indented member
   rows, loose rows after; moving is an edit-mode control per checklist. No
   second navigation surface.
5. **Full folder CRUD + watch sections** — create, rename, reorder (up/down,
   reusing `checklistMoveControls`' shape), delete; folder name captured by an
   alert `TextField` with `uniqueName`-style disambiguation. The watch list
   gains `Section`s per folder plus a loose section, consuming the same model.
6. **Folder identity and LWW clocks mirror `Checklist`** — `Folder` gets
   `id`, `name`, `modifiedAt`, `revision`; `FolderTombstone` mirrors
   `ChecklistTombstone` (`Checklist.swift:307`) with `folderID`, `deletedAt`,
   `revision`. Merge wins by the same `wins` rule (`ChecklistMerge.swift:216-221`).

## What We're NOT Doing

- No separate `folders.v1` key, second store, or second sync transport.
- No per-folder ordering of member checklists (members stay in global order).
- No nesting (folders in folders), no smart/rules folders.
- No relocation of *items* between checklists; moving folders affects checklists
  only.
- No folder support in import/export beyond the `folderID` already riding in the
  envelope (existing `ChecklistExport` untouched unless a test forces it).
- No new SwiftUI List/`onMove`/swipe/context-menu machinery — extend the
  existing `isEditing` row controls.
- No changes to reminder creation or destinations.
- No child tickets; all work lands on the main ticket.

## Open Risks

- **Merge correctness for folders**: `ChecklistMerge` has no array-merge
  precedent for a second entity; folder merge (create/rename/delete/reorder)
  needs its own tests and an idempotence check alongside `apply(remote:)`.
- **Cross-reference skew**: a checklist may arrive with a `folderID` whose
  `Folder` is not yet merged/known; the view must degrade gracefully (render it
  as loose) rather than dropping the checklist.
- **Watch VM shape**: `WatchChecklistViewModel`'s exposure of folders is not yet
  surveyed; if it can't express groups, a small read-only grouping type is
  needed in core, not in the watch target.
- **Envelope `contentEquals`** (`Checklist.swift:361-366`) must include
  `folders`/`folderTombstones` or remote pushes may be skipped as "equal".
- **Localization breadth**: folder strings touch App + Watch catalogs and both
  `requiredKeys` lists; the non-English-differs canary will reject placeholders.
- **UI smoke**: the single XCTest smoke case asserts on current accessibility
  identifiers; new edit-mode-only controls may shift identifiers.