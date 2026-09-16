# Phase 1 output — Edit mode + remove checklists

## Commit
`1101284d1bf0752bbd3c730f2a6319856a2d99cd` — `feat: add checklist edit mode with removal from the main screen`
Pushed to `origin/alanvardy-var-1025-edit-checklists` (force-with-lease, supervisor-approved; the mandated `git rebase origin/main` rewrote the baseline start commit, so the stale remote could not fast-forward). Remote tip verified == local HEAD.

## Changes
- `CheckStitch/ChecklistStore.swift` — new public `func removeChecklists(at offsets: IndexSet)`: one whole-checklist tombstone (`itemID: nil`) per removed checklist in one `save()`, out-of-range/empty offsets are silent no-ops. `moved<T>`, `delete(id:)`, `save()` untouched.
- `CheckStitchTests/ChecklistStoreTests.swift` — `makeChecklistStore(defaults:names:)` fixture + `// MARK: - removeChecklists` section with the 6 planned tests.
- `CheckStitch/Localizable.xcstrings` — new `"Edit"` key, all six languages (en Edit, de Bearbeiten, es Editar, fr Modifier, ja 編集, zh-Hans 编辑), alphabetical placement.
- `CheckStitchTests/LocalizationFixtures.swift` — `"Edit",` inserted alphabetically in the App list (between "Duplicate Checklist" and "Edit checklist").
- `CheckStitch/ContentView.swift` — `@State isEditing`/`checklistPendingRemoval`, shared `editToggleButton` (accessibilityIdentifier `editChecklistsButton`), `checklistList` wrapped in `VStack(spacing: 0)` with a plated right-aligned iOS header row, macOS toolbar third item (hidden when empty), edit-mode `checklistRow` (leading red minus `removeChecklist-<uuid>`, no NavigationLink/run button in edit mode), `removeChecklist(id:)` helper, `confirmationDialog` (confirmRemoveChecklistButton / cancelRemoveChecklistButton), `.onChange(of: store.checklists.isEmpty)` to exit edit mode.

## Automated verification
- `make test-unit` — PASSED (237 tests in 33 suites; includes the 6 new removeChecklists tests and LocalizationTests for "Edit")
- Targeted xcodebuild run of the 6 `testRemoveChecklists*` tests — PASSED (6/6)
- `make build` — PASSED (iOS sim, `#if os(iOS)` header path)
- `make build-mac` — PASSED (macOS toolbar path)
- `make test-ui` — PASSED (1 smoke, 0 failures; existing identifiers unchanged)

## plan.md status
Phase 1 automated items: all four checked (`- [x]`). Manual items remain unchecked for the user.

## Observations
- The `checklistList` restructure moved the `.padding(.top, …)`/`.padding(.bottom, 16)`/`.frame(maxWidth: .infinity)` from the `LazyVStack` onto the wrapping `VStack` as planned; the plate background/overlay stay on the `LazyVStack` exactly as before.
- Push required supervisor-approved `--force-with-lease`: the mandated baseline rebase (origin/main) rewrote the branch's start commit, making the remote non-fast-forward. Remote now matches local.

## Out-of-scope notes
- `DELETEME` placeholder exists on the branch from the start commit; untouched by this phase (left for the merge step).
- The worktree `ScrollView`'s `.simulator_id` (58EBA511-…) was booted headlessly for `make test-ui` and left booted; the full gate handles its own shutdown.