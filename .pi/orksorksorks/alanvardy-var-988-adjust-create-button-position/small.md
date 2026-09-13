# Task

On the main screen's toolbar, the left margin around the create button is
larger than the right margin around the settings button. Make the create
button's left margin equal to the settings button's right margin, and leave
the settings button (and its right margin) exactly as it is. This is a pure
cosmetic spacing fix — no behaviour, accessibility labels, or identifiers
should change.

## Why SMALL

Single-file UI spacing tweak following the existing toolbar layout pattern;
zero unknowns, no schema/API change, no shared code, no design decision, and
no test surface.

## Key files

- `CheckStitch/ContentView.swift` — the toolbar around lines 39–46: the
  create button uses `createButtonPlacement` (line 120) and the settings
  button sits under `settingsButton` (line 168); adjust the leading/margin
  applied to the create button so it matches the settings button's trailing
  margin.