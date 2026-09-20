# Task

The "No checklists" empty state needs a card behind it so the text stays
visible when the checklist list is empty. In `CheckStitch/ContentView.swift`,
the `emptyState` view expands a `ScrollView { ContentUnavailableView { ... } }`
showing a "No checklists" label. Give the "No checklists" label (and the
empty-state content) a card plate behind it — following the existing
`CardPlate` pattern already used for checklist cards in
`CheckStitch/ContentView.swift` and `CheckStitch/CardPlate.swift` — so the
label/description/actions sit on a visible card rather than directly on the
background.

Build on the simulator and verify the empty state (a fresh simulator with no
checklists) renders the card behind the "No checklists" text, per the
repo's icon/render verification convention.

## Why SMALL

Single module/screen view (`ContentView.swift` + the `CardPlate` helper it
already imports), a pure UI styling tweak following an existing in-repo card
pattern (A, B, D, E); no schema, no new subsystem, no design decision; no new
test infrastructure beyond the existing build + UI smoke (C, F).

## Key files

- `CheckStitch/ContentView.swift` — `emptyState` view (circa line 474) is the
  target; `CardPlate.plateFill`/`CardPlate.cornerRadius` are the existing card
  primitives (see usage around lines 397, 288, 321).
- `CheckStitch/CardPlate.swift` — card plate style helpers to reuse.