# Task

Checklists currently stretch edge-to-edge on iPad and iOS. Give the checklist
content a maximum width so it doesn't fill the whole screen. The reference
implementation lives in the sibling project `/Users/vardy/dev/SingleThread`
(`EKReminder` + Reminders UI) — find how it constrains its list width and
apply the same pattern here in CheckStitch.

Scope: `CheckStitch/ContentView.swift` only (this is the sole screen in the
one app target — no other files exist to touch). The app uses
`PBXFileSystemSynchronizedRootGroup`, so no `project.pbxproj` edits are
needed. There is no test target; the gate is `./scripts/test.sh` (build +
shellcheck over `scripts/`).

## Why SMALL

All of A–F hold: single module / single file following an existing pattern
(SingleThread reference), 0 unknowns (the pattern to copy is named in the
ticket), no schema/migration, no new subsystem or shared/convention code, no
design decision (apply the same as SingleThread), no tests — the build is the
gate.

## Key files

- `CheckStitch/ContentView.swift` — the entire UI; the checklist surface lives
  here.
- Reference: `/Users/vardy/dev/SingleThread` — copy its max-width constraint
  pattern.