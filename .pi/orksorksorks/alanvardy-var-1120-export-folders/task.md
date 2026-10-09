# Task

Make checklist import/export preserve folders. Folders (`Folder` + `folderID`
membership + `folderTombstones`) are fully persisted in the model and already
serialized by the version-5 `ChecklistEnvelope`/`ChecklistCodec` — they flow
through iCloud sync and Watch — but they are silently dropped on the export and
import paths: `ChecklistExport.envelope` constructs the envelope with `folders`/
`folderTombstones` left empty, `ChecklistImportSession.decoded()` reads only
`envelope.checklists`, and `ChecklistStore.freshCopy`/`importInsert`/
`importReplace` construct imported checklists without a `folderID`. Exporting a
checklist therefore loses its folder membership.

This task requires a research + design step first (why: no schema change — the
format already supports folders; the design problem is import reconstruction
semantics: match/merge by folder ID vs name, cross-device ID collisions,
orphaned `folderID`s, and whether `folderTombstones`/`isCollapsed` carry
through), then the implementation and review tail.