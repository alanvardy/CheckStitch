# Task

Add JSON import and export of checklists to CheckStitch. Export: the user multi-selects checklists, written as a `CheckStitch-<date>.json` document via `.fileExporter` / `ShareLink`, reusing `ChecklistCodec` / `ChecklistEnvelope` so an export is a valid codec payload and the round trip is lossless; what the export carries (checklists only is the sane default) and how `deviceID`/`tombstones` are treated on import are deferred design decisions.

Import: `.fileImporter`, decode via `ChecklistCodec.classify` (unsupported version or unreadable file surfaces an error rather than importing nothing silently), detect conflicts via `ChecklistStore.sameName` (case-insensitive trimmed names), prompt per conflicting checklist to replace or keep (never overwrite without confirmation), and route every replace/insert through `ChecklistStore` so a replace records a tombstone and changes push via `ChecklistSyncService`.

Tests cover export selection, the encode → classify → decode round trip, conflict replace, conflict skip, and rejection of corrupt or unsupported-version payloads.