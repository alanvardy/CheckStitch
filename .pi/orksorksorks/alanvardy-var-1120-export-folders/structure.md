# Structure Outline

## Approach
The v5 envelope already carries folders (`folders`/`folderTombstones`, decode-defaulted, always
written), so **no schema or version change**. Export must stop falling through the envelope init's
empty-array defaults and pass the folders *referenced by the selected checklists* (deduped, empty
tombstones, `deviceID: ""`); import must resolve each file folder **by name** against local folders,
create the missing ones, and reparent imported checklists through a folder-aware store entry. The
file's folder UUIDs are join keys only; the store mints fresh identities.

## Phase 1: Walking skeleton — export/reimport reconstructs folder membership end to end
A user exports a selected checklist that lives in "Groceries"; the written JSON contains the
"Groceries" folder; importing that file into an **empty** store creates a "Groceries" folder and
lands the checklist inside it. Re-importing the same file creates no duplicate folder. Green tests
prove the envelope carries the folder and the commit path reparents the checklist.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`,
`CheckStitch/ChecklistImportSession.swift`,
`CheckStitch/ChecklistImportExportViewModel.swift`,
`CheckStitchTests/{ChecklistExportTests,ChecklistImportSessionTests,ChecklistImportExportViewModelTests}.swift`

**Key changes**:
- `ChecklistExport.envelope(checklists: [Checklist], from folders: [Folder]) -> ChecklistEnvelope`
  — explicit `folders:`; internally `folders.filter { ids.contains($0.id) }` where `ids =
  Set(checklists.compactMap(\.folderID))`, `folderTombstones: []`. **No default argument** (the
  default is exactly the bug). `data(checklists:from:)` mirrors it.
- `ChecklistStore.resolveOrCreateFolder(named: String) -> UUID` — trimmed, `sameName` reuse else
  mint `Folder(name:, modifiedAt: now(), revision: 1)` in memory; **no `save()`** (caller's write
  pairs it). Returns the local folder id.
- `ChecklistStore.importInsert(_:as:folderID: UUID? = nil) -> UUID` and private
  `freshCopy(of:folderID:)` — carries the resolved folder onto the copy; default `nil` keeps
  `duplicate`/Replace callers unchanged.
- `ChecklistImportSession`: `decoded(_:) -> ChecklistEnvelope` (was `[Checklist]`); stash
  `private var fileFolders: [Folder]` in `stage`. `commit` first builds
  `folderMap: [UUID: UUID]` (file folder id → local id) via `resolveOrCreateFolder`, then calls
  `importInsert(candidate.checklist, folderID: folderMap[candidate.checklist.folderID])`.
- `ChecklistImportExportViewModel.exportSelected`/`shareSelected` pass `from: store.folders`.

**Contract** (next slice consumes, never internals): `importInsert(_:as:folderID:)`,
`importReplace(id:with:folderID:)` (declared now, folder-wired in Phase 2), and the session's
private `folderMap`/`localFolderID(forFileFolderID:)` resolution helper — commit-time, read-only in
`stage`.

**Tests**: `ChecklistExportTests` — exported envelope carries referenced folders deduped and
`folderTombstones == []`, `tombstones == []`, `deviceID == ""`; `ChecklistImportSessionTests` —
round trip into empty store yields the folder name + membership; re-import twice → one folder;
`ChecklistStoreTests` — `resolveOrCreateFolder` reuses on `sameName` and mints on absent with one
save; `ChecklistImportExportViewModelTests` — `exportSelected` writes a folder-bearing payload.
**Verify**: `make test-unit` green for this slice.

---

## Phase 2: Conflict decisions carry folder membership
Importing a file over an existing same-named checklist keeps the folder: `.replace` reparents the
survivor into the file's folder, `.keepBoth`'s copy lands in the imported folder, `.keepExisting`
leaves folders untouched.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift`,
`CheckStitch/ChecklistImportSession.swift`, `CheckStitchTests/ChecklistImportSessionTests.swift`

**Key changes**:
- `ChecklistStore.importReplace(id: UUID, with: Checklist, folderID: UUID? = nil) -> UUID?` —
  folder passed into `freshCopy`; tombstone/`save()` behavior unchanged.
- `ChecklistImportSession.decide(_:for:)` resolves the candidate's file folder via the Phase 1
  helper and forwards `folderID` on `.replace` and `.keepBoth`.
- `.keepExisting` branches earlier and writes nothing (already true).

**Contract**: `decide` is the only consumer of `localFolderID(forFileFolderID:)` after Phase 1's
`commit`; the helper stays private and commit-time.

**Tests**: `ChecklistImportSessionTests` — replace reparents to the file folder (and to loose when
unresolved); keepBoth copy lands in the imported folder; keepExisting leaves local folders
unchanged.
**Verify**: `make test-unit` green for this slice.

---

## Phase 3: Hardening — orphans, collapse state, ignored tombstones, collisions
Edge inputs degrade safely and the design's open risks are pinned.

**Files**: `CheckStitch/ChecklistImportSession.swift`,
`CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift`,
`CheckStitchTests/{ChecklistImportSessionTests,ChecklistExportTests,ChecklistStoreTests}.swift`

**Key changes**:
- Orphan handling: a checklist whose `folderID` is absent from `fileFolders` (or `nil`) → `folderID
  = nil`, no fabricated folder.
- `isCollapsed`: adopted on create (`resolveOrCreateFolder` carries the file value), local value
  kept on `sameName` reuse.
- File `folderTombstones` never read; import never deletes/renames a local folder.
- Duplicate-named folders within one file collapse to a single local folder (name-keyed map).
- Export keeps explicit empty tombstones and no foreign `deviceID` (regression assertion, not new
  code).

**Contract**: no new surface — behavior is fixed against the Phase 1/2 signatures.

**Tests**: orphan `folderID` → loose, no crash; collapse adopt-on-create vs keep-local-on-reuse;
file tombstone ignored (local folder survives); two same-named file folders → one local folder;
renamed local folder → new folder created (documented consequence); export invariant trio.
**Verify**: `make test-unit` green, then `./scripts/test.sh` prints `gate: ok`.

---

## Testing Checkpoints
- After Phase 1: `make test-unit` green — round trip into an empty store and re-import idempotency.
- After Phase 2: `make test-unit` green — `.replace`/`.keepBoth`/`.keepExisting` folder behavior.
- After Phase 3: `./scripts/test.sh` prints `gate: ok` — full gate, warnings-as-errors, shell tests.
- Manual (optional): export a foldered checklist → import into a fresh simulator install → the
  checklist appears under a folder of the same name.
