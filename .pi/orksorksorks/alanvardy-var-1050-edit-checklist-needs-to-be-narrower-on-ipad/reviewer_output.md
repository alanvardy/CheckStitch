## Review

I reviewed the current state of both edited files plus the width type and the main-list precedent. I could not run `git show 55b7069` (no shell/write tools), so I reviewed the files as they stand, cross-referenced against `ChecklistWidth.swift` and `ContentView.swift`. The described change is exactly: wrap each `body` in a `GeometryReader` and add `.frame(maxWidth: ChecklistWidth.maxContentWidth(viewportWidth: geometry.size.width), alignment: .center)` to the content in both screens.

### Correctness

- **ChecklistDetailView.swift:39 (`GeometryReader`) + :194 (`.frame`)**: The `GeometryReader` wraps the whole `if let … else if !isRemoving …` body; `.frame(…)` is attached only to the `Form` inside the `if` branch (`:194`, last modifier in the chain after `.confirmationDialog`), so it constrains just the edit content. The `else if !isRemoving` delete-avoidance logic (`:196-199`) is unchanged in structure and is not accidentally framed. Happy path correctly caps+centers on wide viewports; matches `ContentView.swift:344/356` precedent.
- **ItemEditView.swift:75 (`GeometryReader`) + :83 (`.frame`)**: Frame applied to the outer `Group` after `.settingsSubscreenLayout()` (`:82`), so modifier order is correct — on macOS `settingsSubscreenLayout()` is `modifier(SettingsSubscreenLayout())` (a `maxHeight: .infinity, alignment: .top` fill), and the frame sits outside it, giving width-cap + center while retaining the vertical fill. On iOS `settingsSubscreenLayout()` is a no-op; frame applies cleanly. `.onAppear`/`.onDisappear` chained after the frame are unaffected.
- The width value used is identical to the main list (`min(340, viewportWidth*0.6)`), and `geometry.size.width` is captured exactly like `ContentView.swift:344/356`. No logic error in either branch structure, modifier chain, or GeometryReader wrapping.
- Note: this change also narrows *iPhone* content (0.6×390 ≈ 234pt), not just iPad — but that is precisely what the main list already does, so it makes the two screens consistent rather than introducing a regression. Not an issue.

### Conventions (AGENTS.md)
- No forced unwraps (uses `guard … else`, `if let`); no unused variables (`geometry`, `checklist`/`item` all used); imports (`CheckStitchCore`, `SwiftUI`) already present and used; WARNINGS_AS_ERRORS build already passed.

### Findings

- Correct: the change achieves the intended effect — both the edit-checklist Form and item-edit Group are now width-capped and centered on wide viewports, mirroring the main list. Branch-structure refactor (`if let … else if !isRemoving` / `if let … else`) preserved pre-existing behavior unchanged.
- Fixed: none (read-only).
- Finding:
  - **P2** — Coverage of the sad path is inconsistent between the two screens. `ChecklistDetailView.swift:194` frames only the `if` branch, so `ContentUnavailableView("Checklist not found")` (`:197-198`) stays full-width/edge-to-edge on a wide iPad, whereas `ItemEditView.swift:83` frames the outer `Group`, so its `ContentUnavailableView("Item not found")` (`:79-80`) *is* capped. Minor cosmetic inconsistency on transient deleted-while-open states; matches the main list's uncapped `emptyState` precedent. Smallest fix: move the `.frame` onto a wrapping group in `ChecklistDetailView` (as done in `ItemEditView`), or accept as-is.
  - **P2 (informational)** — The `ChecklistWidth` references at `ChecklistDetailView.swift:194` and `ItemEditView.swift:83` may resolve to the app-target's file-local `enum ChecklistWidth` at `ContentView.swift:550` (repo-documented module shadowing of the CheckStitchCore public type), rather than the public `CheckStitchCore/…/ChecklistWidth.swift:9` type the ticket claims to use. Both definitions are behaviorally identical (`min(340, viewportWidth*0.6)`), so it has no functional impact — worth knowing only because the "uses the public reusable type" framing is imprecise.
  - **P2 (nit)** — `ChecklistDetailView.swift:194` and `ItemEditView.swift:83` are ~114 chars, notably longer than the ~98-char equivalent in `ContentView.swift:344/356` (which drops the `, alignment: .center`). No line-length rule is enforced (no `.editorconfig`), so cosmetic only.

### Merge verdict
**OK** — the change is correct and convention-compliant (including the already-passing WARNINGS_AS_ERRORS build / 361 unit tests). The three P2 items are optional polish, none block merge.