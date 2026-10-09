# Design Discussion

## Current State

Folders (`Folder`, `checklist.folderID`, `FolderTombstone`) are fully modeled and
serialized on the **version-5 `ChecklistEnvelope`**, which has six fields —
`version, deviceID, checklists, tombstones, folders, folderTombstones`
(`Checklist.swift:506-510`) — and always writes all six (`:574-587`). Folders flow
through iCloud sync and Watch, but are dropped on the export and import paths:

- **Export is the only envelope producer that omits folders.**
  `ChecklistExport.envelope(checklists:)` builds
  `ChecklistEnvelope(version:, deviceID: "", checklists:, tombstones: [])` and
  relies on the envelope init's `folders = []` / `folderTombstones = []` defaults
  (`ChecklistExport.swift:8-12`, defaults `Checklist.swift:517-519`). The docstring
  pins the intent: no device identity, no tombstones (`ChecklistExport.swift:3-6`).
  Every other producer passes folders explicitly
  (`ChecklistSyncCoordinator.swift:47`, `ChecklistMerge.swift:38-39`).
- **Import consumes only `version` + `checklists`.**
  `ChecklistImportSession.decoded(_:)` classifies and maps
  `envelope.checklists`; `folders`/`folderTombstones` decode but are never read
  (`ChecklistImportSession.swift:96-104`, decode `Checklist.swift:529-541`).
- **`freshCopy` additionally drops `folderID`.** It preserves name, destination,
  prefixes flag, watch flag, `multiple`, and per-item title/description/
  relativeDate/priority, but regenerates items, resets archive, drops `folderID`,
  `itemOrder` and legacy revisions (`ChecklistStore.swift:274-290`). It backs
  `importInsert` (`:298-306`), `importReplace` (`:312-324`) and `duplicate`.

So folder loss has two independent drop points: envelope level (export omits,
import ignores) and checklist level (`freshCopy` discards the pointer).

Folder identity is a **UUID pointer with no folder-side children list**;
`ChecklistGrouping`/`visibleFolders` derive entirely from
`checklist.folderID == folder.id` and treat an unknown id as loose (research Q3).
Import conflict handling is checklist-name-only: `conflictingChecklist(named:)`,
`sameName` case-insensitive/trimmed, `uniqueName` `base`→`base 2`
(`ChecklistStore.swift:200-203,407-425`); `ImportDecision {replace,keepBoth,
keepExisting}` (`ChecklistImportSession.swift:124-141`). No version or schema
change is required: the v5 format already carries folders.

## Desired End State

Exporting a selection writes the folders needed to reconstruct its grouping, and
importing that file reconstructs folder membership:

- **Export** carries `folders` = the folders referenced by the selected
  checklists (deduped by id), `folderTombstones = []`, `deviceID = ""`,
  `tombstones = []`. The "gift, not a delete instruction" invariant is preserved.
- **Import** resolves each file folder to a local folder **by name** and assigns
  member checklists to it; folders absent locally are created. The file's folder
  UUIDs are join keys only and never become local identity.
- Verify by: `make test-unit` (fast) then `./scripts/test.sh` (gate).

Correct means:
1. Export → import into an empty store recreates the same folder names and the
   same checklist→folder membership.
2. Re-importing the same file twice does **not** duplicate folders.
3. Importing a folder alongside checklists when the store has **no** folders
   creates the folder (explicit requirement).
4. Orphan `folderID` (folder absent from the file) lands loose, no crash.
5. Existing folderless import/export behavior and the checklist conflict flow are
   unchanged.

## Patterns to Follow

Good patterns to match:

- **Explicit folder passing on envelope construction** — mirror
  `ChecklistSyncCoordinator.swift:47` (`folders: folders()`) rather than relying on
  the envelope init defaults, which is the bug in `ChecklistExport.swift:8-12`.
- **Folder minting + name disambiguation** — reuse the `createFolder` shape:
  trimmed name, `uniqueName` against existing folder names, `Folder(name:,
  modifiedAt: now(), revision: 1)`, single `save()` (`ChecklistStore.swift:601-607,
  407-416`). Name comparison convention is `sameName` (`:420-425`).
- **Selection filtering** — `exportSelected`/`shareSelected` filter
  `store.activeChecklists` by `exportSelection`
  (`ChecklistImportExportViewModel.swift:56-63,69-78`); folder scope should derive
  from the same filtered set.
- **Single-save write ops** — `importInsert`/`importReplace` each perform one
  `save()` (`ChecklistStore.swift:298-324`); folder materialization should join
  that save, not add per-folder saves.
- **Test construction** — encode with `ChecklistCodec.encode`, decode with
  `ChecklistCodec.classify`, assert semantically, never byte-compare
  (`ChecklistExportTests.swift:24-33,159-173`); isolated store +
  `payload(_:version:)` helper (`ChecklistImportSessionTests.swift:6-18`); no
  shared folder fixture — build `Folder(name:)` inline and link via `folderID`
  (conventions.md).

Patterns NOT to follow:

- **Merge's non-revalidation of `folderID`** (`ChecklistMerge.swift:144` copies a
  checklist's `folderID` wholesale on an LWW win; nothing checks live/dead
  folders). Import must resolve against the folders it is about to create, not
  leave a dangling pointer and rely on grouping's loose fallback.
- **Implicit empty-array defaults on export** — do not let `folders` fall through
  the init default again; pass it explicitly with a test pinning it.

## Design Decisions

1. **Export folder scope — referenced only**: include, deduped by id, exactly the
   folders that selected checklists point at. The file is a checklist export, not
   a store backup; `folderID` is the only membership link, so referenced folders
   are precisely what reconstruction needs.
2. **Export `folderTombstones` — empty**: keeps the documented no-resurrection /
   no-foreign-device invariant (`ChecklistExport.swift:3-6`). A tombstone in a
   shared file would prune a recipient's folder (`ChecklistMerge.swift:33-36`).
3. **Import matching — name only**: resolve file folders by case-insensitive,
   trimmed name (`sameName`); reuse a local folder on match. The file's folder
   `id` ↔ `checklist.folderID` link is used *only* to recover each checklist's
   folder **name**; ids never cross into the store as identity.
4. **New-folder identity — fresh store UUID**: on no match, create a folder via
   the `createFolder` path, letting the store mint the UUID. No imported-uuid
   preservation and therefore no live-id/tombstone collision guard.
5. **Create when absent**: if the local store has no matching folder — including
   the store having **zero** folders — create it. This is the explicit
   requirement for the "import has folders, local has none" case.
6. **`isCollapsed` — adopt on create, keep local on reuse**: imported collapse
   state applies to folders we create; an existing local folder keeps its value.
   It is per-device display state (`Folder.isCollapsed`).
7. **File `folderTombstones` — ignored**: import never deletes local folders.
8. **Orphan `folderID` — loose**: a checklist whose folder does not appear in the
   file lands with `folderID = nil`; no fabricated folder.
9. **`.replace` — imported folder wins**: the replacement lands in the file's
   folder (loose if unresolved), consistent with `importReplace` swapping the
   whole checklist body (`ChecklistStore.swift:312-324`).
10. **UI — silent**: folders are reconstructed at commit; the import preview and
    `ImportDecision` stay checklist-only. No new strings or localization work.
11. **Resolution timing — commit-time**: `stage` remains read-only (it writes
    nothing, `ChecklistImportSession.swift:55-69`); folder resolution/creation
    happens inside `commit`/`decide`, and `keepBoth` copies land in the imported
    folder while `keepExisting` leaves folders untouched.
12. **No schema/version change**: the payload stays v5; folders are already part
    of it.

Sketch (implementation detail, not a commitment): a `ChecklistImportSession`
step computes a `file-folder-id → local-folder-id` map from the decoded envelope
(after name matching/creation), and the store gains a folder-aware import entry
(e.g. `importInsert(_:as:folderID:)` / `importReplace(id:with:folderID:)`) plus a
`resolveOrCreateFolder(named:)` that mints in memory so the checklist write and
folder creation share the existing single `save()`.

## What We're NOT Doing

- **No format/version change** — no new field, no v6; v5 already carries folders.
- **No folder conflict UI** — no folder rows in the import preview, no per-folder
  merge/keep choices, no new `Localizable.xcstrings` keys.
- **No imported folder UUIDs** — file ids are join keys, never local identity.
- **No tombstone traffic** — export ships none; import ignores any it sees.
- **No destructive import** — never delete or rename a local folder on import.
- **No nesting / parent folders** — folders stay flat.
- **No sync/merge/Watch changes** — `ChecklistMerge`, `ChecklistSyncCoordinator`
  and the Watch context path are untouched.
- **No `duplicate` behavior change** — fixing `duplicate` to keep its folder is a
  separate follow-up; `freshCopy`'s new parameter must default to today's
  drop-folder behavior for the duplicate caller.

## Open Risks

- **Name collisions in the file**: two file folders with the same name collapse to
  one local folder. Well-formed exports cannot produce this (`uniqueName` at
  creation, `ChecklistStore.swift:601-607`), but a hand-edited file could.
- **Local rename**: if the recipient renamed their folder, the old name no longer
  matches, so import creates a second folder; idempotency is name-based, not
  id-based (an accepted consequence of the name-only decision).
- **Same-name, different-intent folder**: imported checklists merge into an
  unrelated local folder that happens to share the name — accepted.
- **`freshCopy` signature ripple**: adding a folder parameter touches `duplicate`
  and any other caller; defaulting preserves current behavior but the default is
  easy to forget at the import call sites.
- **Watch/UI rendering of `isCollapsed`** was not traced (research Open Areas);
  adopting it on create is safe but its visible effect on Watch is unverified.
- **Grill cap reached** with Q7–Q10 accepted as recommended by the user's
  "rest recommended" direction; if any of `isCollapsed`, file-tombstones, orphans,
  or replace-folder semantics should differ, raise it before planning.