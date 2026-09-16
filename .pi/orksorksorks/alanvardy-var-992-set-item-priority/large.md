# Task

Add a priority to checklist items in CheckStitch. Each item row in the
edit-checklist screen (`CheckStitch/ItemEditView.swift`) gets an info button on
the right that opens an overlay for selecting the item's priority. `priority`
currently exists nowhere in the codebase — it must be added to the canonical
`ChecklistItem` model in `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
(a `Codable` struct with per-field revision/modifiedAt sync machinery, explicit
back-compat decode obligations for old payloads, and round-trips through the
codec, store, sync, merge and import/export surfaces).

## Why LARGE

SCHEMA + CONVENTION_RISK + CROSS_CUTTING (data model/storage + UI surfaces):
adding a persisted field to the synced `ChecklistItem` model changes the codec
payload / persistence format, which the repo treats as a first-class compat
invariant ("additive optional field: absent key decodes", "encoder writes every
key", "v1 payloads still load"); the field must also flow through the
sync/merge/revision machinery and a new UI overlay, and the ticket leaves the
priority value set unspecified.