# Task

Make checklist import/export preserve folders. Today folders (`Folder` + `folderID`
membership + `folderTombstones`) are fully persisted in the model and already
serialized by the version-5 `ChecklistEnvelope`/`ChecklistCodec` — they flow
through iCloud sync and Watch — but they are silently dropped on the export and
import paths: `ChecklistExport.envelope` constructs the envelope with `folders`/
`folderTombstones` left empty, `ChecklistImportSession.decoded()` reads only
`envelope.checklists`, and `ChecklistStore.freshCopy`/`importInsert`/
`importReplace` construct imported checklists without a `folderID`. Exporting a
checklist therefore loses its folder membership.

This task requires a research + design step first (why: see below), then the
implementation and review tail.

## Why LARGE

Matched triggers: **DESIGN_SIGN-OFF** + **UNKNOWNS** (+ CROSS_CUTTING breadth).

- There is **no data-model or schema/migration change** — the format already
  supports folders. The design problem is import reconstruction semantics: the
  export deliberately sets `deviceID: ""` and ships no tombstones so import
  cannot resurrect deletions or inject a foreign device id. Deciding how folders
  rebuild on import within those constraints — match/merge by folder ID vs by
  name, handling cross-device ID collisions, orphaned `folderID`s referencing
  folders absent from the file or locally, whether `folderTombstones` and the
  `isCollapsed` state carry through export — is a genuine design decision with
  several viable alternatives that needs human sign-off, and the merge behavior
  shares the existing `ChecklistMerge` codec/sync semantics so a wrong call
  risks corruption.
- Several import edge cases are open (≥3 unknowns) and the store currently
  discards `folderID` by design, so the identity/merge model for imported
  folders must be re-derived.
- Scope is broad and multi-module: export (`ChecklistExport.swift`,
  `ChecklistExportDocument.swift`, `ChecklistShare.swift`,
  `ChecklistImportExportViewModel.swift`, `ExportChecklistsView.swift`), import
  (`ChecklistImportSession.swift`, `ChecklistImportExportViewModel.swift`),
  store (`ChecklistStore.freshCopy`/`importInsert`/`importReplace`), plus a wide
  test surface.

## Key files (from recon)

- Export: `ChecklistExport.swift` (envelope() leaves folders empty),
  `ChecklistExportDocument.swift`, `ChecklistShare.swift`,
  `ChecklistImportExportViewModel.swift`, `ExportChecklistsView.swift`
- Data model / codec (already folder-capable, do not change schema):
  `ChecklistCore/Sources/ChecklistCore/Checklist.swift` (`Folder` :445,
  `ChecklistEnvelope` :506, `ChecklistCodec` :565, v5 :598-601, `folderID` on
  Checklist :234-238/284/320-323, `ChecklistGrouping` :651 read-only derivation)
- Import: `ChecklistImportSession.swift` (decoded() :96-107 ignores envelope
  folders), `ChecklistStore.swift` (freshCopy :291-315/importInsert :298-329
  drop folderID; live folder CRUD createFolder/moveChecklist/renameFolder/
  deleteFolder :601-674)
- Reference live folder paths already threaded for folders:
  `ChecklistSyncService.swift`, `ChecklistSyncCoordinator.swift` (pushContext
  encodes folders), `ChecklistMerge.swift` (merge folds folders)
- Tests needing folder cases: `ChecklistExportTests.swift`,
  `ChecklistExportDocumentTests.swift`, `ChecklistImportSessionTests.swift` (0
  folder coverage), `ChecklistStoreTests.swift`, `ChecklistImportExportViewModelTests`,
  `ChecklistCodecTests.swift`