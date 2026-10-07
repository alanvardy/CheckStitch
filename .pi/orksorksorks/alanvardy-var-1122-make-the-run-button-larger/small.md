# Task

On the main screen, the "Run" button next to a checklist's name is too small.
Make it square and have it fill all the vertical space available in the row —
so it becomes a full-height square button in the checklist row.

Scope: the checklist row on the main screen (`CheckStitch/ContentView.swift`).
Follow existing SwiftUI patterns in that file. Verify any UI change with
`make build`, and run `make test-unit` before the full gate
(`bash scripts/test.sh`).

## Why SMALL

Localized one-file UI change following an existing pattern; no schema,
no new subsystem/integration, no shared/convention code, no design trade-off,
and tests needed (if any) are few and local.

## Key files

- `CheckStitch/ContentView.swift` — the main screen's checklist row and its Run button.