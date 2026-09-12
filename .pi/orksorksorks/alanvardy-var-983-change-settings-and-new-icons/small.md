# Task

Restyle the two main-screen chrome icons — the Settings gear and the Create
("new") plus — on **iOS only (iPhone and iPad)** so they match the checklist
plate style: a blue (`.tint`) outline with a solid **black** fill in the
middle, instead of the current translucent centre.

Both icons live in `CheckStitch/ContentView.swift` in their iOS branches:

- **Settings gear** — `settingsButton` (iOS arm of `#if os(iOS)`, ~line 123):
  already draws the 52×52 plate with a `RoundedRectangle(cornerRadius: 14)
  .stroke(.tint, lineWidth: 2)`, but the `Image(systemName: "gearshape")`
  glyph stays translucent. Make the gear solid black.
- **Create plus** — the toolbar `ToolbarItem(placement: createButtonPlacement)`
  with `Label("Create checklist", systemImage: "plus")` (~line 38). Give it
  the same treatment as the gear: a blue-outlined plate with a solid black
  plus inside, so it matches the settings button style.

Do **not** change the macOS branches (`#else` arms) — macOS keeps its native
title-bar chrome and plain glyphs, per the existing comment on
`settingsButton`. Keep both buttons' existing accessibility identifiers
(`settingsButton`, `createChecklistButton`) and the `.checkStitchButton()`
modifier untouched. The macOS `createChecklistButton` identifier is asserted
by the UI smoke test, so don't remove the button — only restyle its iOS label.
Prefer reusing the `CardPlate.cornerRadius` / tint-stroke pattern already in
the file over introducing new constants.

## Why SMALL

A–F all hold: single file (`CheckStitch/ContentView.swift`) following the
existing `settingsButton` plate pattern; approach known (solid-black glyph
over the existing blue outline, e.g. `.foregroundStyle(.black)`); no schema,
no new subsystem, no shared/convention code; no design decision — the ticket
specifies the exact target style; no visual tests exist and the UI smoke only
asserts button existence by identifier.

## Key files

- `CheckStitch/ContentView.swift` — `settingsButton` (iOS arm ~line 123) and
  the create toolbar item (~line 38).
- `CheckStitch/CardPlate.swift` — existing radius/plate constants to reuse for
  visual rhythm (no changes expected).