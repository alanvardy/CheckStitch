# Worker Output — narrow checklist-edit screens on iPad

## Task
Constrain the iPad "edit checklist" screen (`ChecklistDetailView.swift`) and its
item-edit subscreen (`ItemEditView.swift`) to a centered column, mirroring the
main list's `ChecklistWidth.maxContentWidth` cap that makes the Settings surface
narrow on wide viewports.

## Recon correction applied
The task premise mentioned `@Environment(\.geometry)`; the actual codebase uses
`GeometryReader { geometry in ... geometry.size.width }` (SwiftUI GeometryReader),
and the reusable cap is the **public** `ChecklistWidth.maxContentWidth` in
`CheckStitchCore/Sources/CheckStitchCore/ChecklistWidth.swift`
(`min(340, viewportWidth * 0.6)`). Reused that; touched no new helper, no
`ContentView.swift`, and left the file-local `ChecklistWidth` enum and the
`ChecklistWidthTests` (pure math, unchanged) alone.

## Changes

### `CheckStitch/ChecklistDetailView.swift` — commit commit 55b7069
- `body` (line 43 on) wrapped — commit 55b7069.
- The `Form`'s modifier chain gains
  `.frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width), alignment: .center)`
  right before the `} else if !isRemoving {` branch, capping the edit form to a
  centered column. The `else` `ContentUnavailableView` branch is inside the
  GeometryReader (consistent), unconstrained.
- Byte-identical Form body otherwise; all lines inside the GeometryReader are
  +4 re-indented.

### `CheckStitch/ItemEditView.swift` — commit 55b7069
- `body` (line 21 on) wrapped — commit 55b7069.
- The `Group`'s modifier chain gains the same
  `.frame(maxWidth: ..., alignment: .center)` right after `.settingsSubscreenLayout()`,
  before `.onAppear`. `.settingsSubscreenLayout()` itself only top-aligns on
  macOS (no-op on iOS) — it does NOT constrain width, so the cap is required.
- Byte-identical body otherwise; +4 re-indent inside the GeometryReader.

## Verification
- `make build` (simulator, `WARNINGS_AS_ERRORS` on): **BUILD SUCCEEDED**.
- `make test-unit` (macOS unit suite): **TEST SUCCEEDED** — 361 tests in 48
  suites passed.
- No test changes: the width math is unchanged, and SwiftUI frame layout is
  compiler-verified (per recon, no SwiftUI layout assertions exist to extend).

## Commit
- `55b7069` — "narrow checklist-edit screens to a centered column on iPad"
- Pushed to `origin/alanvardy-var-1050-edit-checklist-needs-to-be-narrower-on-ipad`.

## Divergence from plan / notes
- Used the public `ChecklistWidth.maxContentWidth` (recon-corrected) rather than
  the task's `@Environment(\.geometry)` description.
- Intentional no-op: line-8 `DELETEME` placeholder present in the worktree from
  the base commit; restored/untouched and not part of this change.
- Full `bash scripts/test.sh` gate intentionally NOT run (per instructions; the
  parent runs it after this commit).