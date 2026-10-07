# Done

- **What was built**: The main-screen checklist row's Run button
  (`createRemindersButton(for:)` in `CheckStitch/ContentView.swift`) keeps its
  enlarged `.font(.title2)` glyph and square tap target, but the row no longer
  grows around it: `checklistRow` now pins its content to
  `CardPlate.checklistRowHeight` (44pt) with only 1pt vertical padding, so the
  Run square is full-row-height (46pt total) while the row stays at its
  pre-ticket, text-driven height. Browse and edit modes share the same fixed
  height, so toggling edit no longer changes the list's rhythm. Run logic,
  disabled state, accessibility label/identifier, and
  `.buttonStyle(.borderless)` are unchanged.
- **Commit SHA(s)**: `d322538` ("Pin checklist rows to a fixed height for the
  larger run icon"), on top of `9a7e5ea` ("Make the checklist run button a
  full-height square"); pushed to `origin/alanvardy-var-1122-make-the-run-button-larger`.
- **Verification**: `make build` (simulator, warnings-as-errors) →
  `** BUILD SUCCEEDED **`; `make test-unit` → 603 tests in 67 suites passed;
  full gate `bash scripts/test.sh` → `gate: ok` (incl. UI smoke, `build-mac`,
  `watch-build`, 26 shell tests, shellcheck).
- **Reviewer findings**: No blockers. Nits deferred: (1) the 44pt Run square
  is a fixed frame rather than `.frame(maxHeight: .infinity)` — acceptable
  because the row height is now pinned to the same 44pt
  (`CardPlate.checklistRowHeight`), so the two agree by construction; (2)
  `.font(.title2)` applies to the whole `Group`, including the small
  `ProgressView` (harmless). No test was added — pure SwiftUI layout has no
  headless seam, and no existing unit/UI test asserts button geometry (the UI
  smoke only checks `.exists`).
- **Remaining manual items**: Optional: confirm the enlarged glyph and the
  unchanged row height visually on a booted simulator/device (`make run`).
