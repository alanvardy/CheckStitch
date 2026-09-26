# Structure Outline

## Approach

Add a `Folder` entity + `folderID: UUID?` on `Checklist` riding in the existing
`checklists.v1` envelope (bumped 4 → 5), then build the feature as vertical
tracer slices: first a walking skeleton that creates a folder and puts a real
checklist inside it (persisted, reloaded, rendered), then fire the riskiest
integration (folder merge/sync) before layering rename/reorder/delete, watch
sections, and finally hardening + localization. Every slice ships its tests.

---

## Phase 1: Walking skeleton — a folder exists and holds a checklist, end to end

The user can, in edit mode, create a folder and move a checklist into it (and
back to loose); the main screen renders folder sections with their members plus
a loose group, and the whole thing survives reload. Its green tests prove the
v5 envelope round-trips and the membership persists.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`,
`CheckStitch/ChecklistStore.swift`, `CheckStitch/ChecklistMerge.swift`,
`CheckStitch/ChecklistListViewModel.swift`, `CheckStitch/ContentView.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`,
`CheckStitchTests/CheckListListViewModelTests.swift`

**Key changes**:
- `struct Folder: Identifiable, Codable, Hashable, Sendable { let id: UUID; var name: String; var revision: Int; var modifiedAt: Date }` — new, beside `ChecklistTombstone`
- `struct FolderTombstone: Codable, Hashable, Sendable { let folderID: UUID; var deletedAt: Date; var revision: Int }` — new (declared here, used in Phase 4)
- `Checklist.folderID: UUID?` — new; `decodeIfPresent(...)` default `nil`, encoded unconditionally
- `ChecklistEnvelope.folders: [Folder]` / `.folderTombstones: [FolderTombstone]` — new, `decodeIfPresent(...) ?? []`; `currentVersion = 5`; `contentEquals` includes both
- `ChecklistStore.folders: [Folder]` — read-only getter in persisted order
- `ChecklistStore.createFolder(name: String? = nil, at: Date = .now()) -> Folder` — `uniqueName`-style default ("New Folder"), append + one `save()`
- `ChecklistStore.moveChecklist(id: UUID, toFolder: UUID?)` — sets `folderID`, bumps `revision`/`modifiedAt` so merge transfers it, one `save()`
- `ChecklistMerge.mergedChecklists` — explicit `folderID` copy line when remote wins
- VM: `folders: [Folder]`, `checklists(in folder: Folder?) -> [Checklist]` (`nil` = loose, existing global order), `createFolder() -> UUID`, `moveChecklist(id:toFolder:)`
- `ContentView`: `folderSection(for:)` header + member rows; loose rows after; edit-row "move to folder" control under `isEditing`

**Contract**: the `Folder`/`FolderTombstone` value types, `Checklist.folderID`,
the v5 envelope shape (folders/folderTombstones additive, version-gated
protection), and the store/VM methods above. A v4 codec reading a v5 payload
must return `.unsupportedVersion`; a v4 payload must load with `folders == []`,
`folderID == nil`.

**Tests**: store — folder create persists/reloads, membership move + reload,
v4 payload decodes with defaults, v5 payload classified `unsupportedVersion` by
a pinned v4 decoder; VM — grouping (`folderSectionsGroupMembers`), loose list,
move updates grouping. Happy + one sad (move to a non-existent folder id is
rejected / leaves membership unchanged).
**Verify**: `make test-unit` green; `make build` green.

---

## Phase 2: Folder merge/sync correctness (risk-front-loaded)

A folder created, renamed, or deleted on one device converges on another via
`ChecklistMerge` without dropping folders or resurrecting deleted ones.

**Files**: `CheckStitch/ChecklistMerge.swift`,
`CheckStitchTests/ChecklistMergeTests.swift`

**Key changes**:
- `ChecklistMerge.merge(local:remote:)` — union `folders` by id with the existing `wins` rule (revision → newer date → smaller device), transfer `name`/`revision`/`modifiedAt`; union `folderTombstones` grow-only; prune tombstoned folders; `contentEquals`-based idempotence guard preserved
- `mergedFolders(local:remote:) -> [Folder]` — new helper mirroring `mergedChecklists`

**Contract**: folder LWW semantics and tombstone pruning, stable under repeated
`apply(remote:)` (idempotent). Remote `folderID` with no matching `Folder`
degrades to loose at read time (asserted here, finalized in Phase 6).

**Tests** (`ChecklistMergeTests`, Swift Testing): remote-only folder unions in;
conflicting name resolves by `wins`; folder tombstone removes the folder and
orphans members; merging the same envelope twice is a no-op; checklist carrying
an unknown `folderID` survives.
**Verify**: `make test-unit` green.

---

## Phase 3: Rename and reorder folders (edit mode)

The user can rename a folder (alert `TextField`, `uniqueName` disambiguation)
and move folders up/down with the same chevron control shape as checklists.

**Files**: `CheckStitch/ChecklistStore.swift`, `CheckStitch/ChecklistListViewModel.swift`,
`CheckStitch/ContentView.swift`, `CheckStitch/Localizable.xcstrings`,
`CheckStitchTests/ChecklistStoreTests.swift`, `CheckStitchTests/CheckListListViewModelTests.swift`

**Key changes**:
- `ChecklistStore.renameFolder(id: UUID, to name: String)` — disambiguates, bumps `revision`/`modifiedAt`, one `save()`
- `ChecklistStore.moveFolders(from: IndexSet, to: Int)` — local-first via `moved<T>`, no revision bump (mirrors `moveChecklists`)
- VM: `renameFolder(id:to:)`, `moveFolder(id:up:)`
- `ContentView`: folder header edit controls (up/down, rename) reusing the
  `checklistMoveControls` shape; alert `TextField` for create + rename

**Contract**: `folders` order is the persisted order; rename bumps the LWW
clock, reorder does not.
**Tests**: store — rename persists + disambiguates, reorder persists, reload
matches; VM — `moveFolder(id:up:)` reorders, rename reflects. Sad path: rename
to an existing name is disambiguated, never dropped.
**Verify**: `make test-unit` green; `make build` green.

---

## Phase 4: Delete a folder, orphaning its checklists

The user can delete a folder from edit mode; its checklists return to loose and
a `FolderTombstone` prevents resurrection on sync.

**Files**: `CheckStitch/ChecklistStore.swift`, `CheckStitch/ChecklistListViewModel.swift`,
`CheckStitch/ContentView.swift`, `CheckStitch/Localizable.xcstrings`,
`CheckStitchTests/ChecklistStoreTests.swift`, `CheckStitch/ChecklistMergeTests.swift`

**Key changes**:
- `ChecklistStore.deleteFolder(id: UUID)` — set affected checklists' `folderID = nil` (bump each member's `revision`/`modifiedAt`), append `FolderTombstone(folderID:deletedAt:revision:)`, one `save()`; never write checklist tombstones
- VM: `folderPendingRemoval: UUID?`, `removeFolder(id:)`
- `ContentView`: staged `.confirmationDialog` on folder header, mirroring `checklistPendingRemoval`

**Contract**: delete = orphan + tombstone, single `save()`; merge prunes the
folder but keeps its checklists.
**Tests**: store — delete orphans members, persists tombstone, survives reload;
merge — tombstoned folder deleted while members survive as loose. Sad path:
delete folder with no members writes only the tombstone.
**Verify**: `make test-unit` green.

---

## Phase 5: Watch shows folders as sections

The watch list renders the same folders as `Section`s plus a loose section,
consuming the core model.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/…` (small read-only grouping
type if the VM can't express groups), `CheckStitchWatch/WatchChecklistViewModel.swift`,
`CheckStitchWatch/WatchChecklistListView.swift`

**Key changes**:
- A read-only grouping surface in core (e.g. `ChecklistGrouping.sections(folders:checklists:) -> [(name: String?, checklists: [Checklist])]`) if the watch VM cannot express it; otherwise watch-local computed groups
- `WatchChecklistListView`: `List { Section(...) }` per folder + loose, `NavigationLink` unchanged

**Contract**: watch consumes only the core grouping type + model; no app-target
store dependency.
**Tests**: core grouping unit test (member order = global order, loose last);
watch compile via gate.
**Verify**: `make test-unit` green; `make watch-build` green.

---

## Phase 6: Hardening, states, and localization

Cross-reference skew, empty states, and all user-facing strings land.

**Files**: `CheckStitch/ContentView.swift`, `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` (grouping),
`CheckStitch/Localizable.xcstrings`, `CheckStitchWatch/Localizable.xcstrings`,
`CheckStitchCore/…/Resources/Localizable.xcstrings`,
`CheckStitchTests/LocalizationFixtures.swift`, `CheckStitchTests/LocalizationTests.swift`,
`CheckStitchUITests/CheckStitchUITests.swift`

**Key changes**:
- Unknown `folderID` renders the checklist in loose (never dropped); empty-folder
  and all-loose states render cleanly
- Every new key (folder, new folder, rename, delete, loose, move-to-folder) in
  **all six languages** in App + Watch + Core catalogs, and in the matching
  `requiredKeys` lists
- UI smoke: confirm accessibility identifiers still resolve with edit-mode controls present

**Contract**: n/a — polish only; no new public signatures.
**Tests**: `LocalizationTests.catalogsHaveAllSixLanguages` +
`everyRequiredKeyIsPresent` + non-English-differs canary; grouping test for
unknown-folder fallback; UI smoke unchanged/updated.
**Verify**: `bash scripts/l10n-check.sh`, `make test-unit`, `make test-ui`, then
full `bash scripts/test.sh` prints `gate: ok`.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` + `make build` green → model/envelope/membership contract is frozen.
- After Phase 2: merge tests green (idempotence included) → sync risk retired.
- After Phase 3: rename/reorder tests green → folder management contract frozen.
- After Phase 4: orphan+tombstone tests green → destructive path safe.
- After Phase 5: `make watch-build` green → watch consumes core only.
- After Phase 6: `bash scripts/test.sh` → `gate: ok` (incl. `make build-mac`, `make watch-build`, shell tests).
- Real-device close-out (per project rules): installed build shows folder sections and moves work.
