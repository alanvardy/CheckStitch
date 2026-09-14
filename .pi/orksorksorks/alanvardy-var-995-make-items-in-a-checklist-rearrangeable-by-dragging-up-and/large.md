# Task

Make items in a checklist rearrangeable by dragging up and down in the edit
screen (`CheckStitch/ChecklistDetailView.swift`), driven by a new
`ChecklistStore.moveItems(checklistID:from:to:)` taking the standard
`IndexSet`/`Int` pair so SwiftUI's `.onMove` can call it directly. A pure
reorder must not be misread as an edit: item identity is per-item
`modifiedAt`/`revision`, and both must stay unchanged by a move.

Before implementing, a design decision must be settled: `ChecklistMerge.mergedItems`
keeps local array order and appends remote-only items, so a local reorder
currently will **not** sync between iPhone/iPad/macOS. The ticket names two
viable designs — accept local-only ordering, or give `ChecklistItem` an
explicit `position`/`sortOrder` field that merges like any other field (a
bigger data-model change touching encoding, merge and the KVS sync path, but
the correct one if ordering must survive sync). This trade-off needs a human
decision before the implement path runs.

Tests must cover: move within the list, move to the end, out-of-range
indices, and unknown checklist id.

## Why LARGE

DESIGN_SIGN-OFF — the ticket explicitly flags a consideration to settle
before implementing with two viable designs and a product trade-off
(local-only ordering vs. a synced `position`/`sortOrder` field); the latter
option also triggers SCHEMA, since it changes the `ChecklistItem` data model
and its merge/encoding/sync behaviour.