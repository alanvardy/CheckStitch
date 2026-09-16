# Implementation Summary

Both phases of the plan implemented, verified, committed and pushed to
`origin/alanvardy-var-1025-edit-checklists`. The plan's 9 automated items are
checked; all 9 manual items are gathered below for the user.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `1101284` | feat: add checklist edit mode with removal from the main screen |
| 2     | `ac283df` | feat: reorder checklists from the main screen edit mode |
| —     | `8b53c14` | docs: check off Phase 2 automated verification in the plan |

## Automated Checks

- [x] `make build` passes (Phase 1 — sim build compiles the `#if os(iOS)` header path)
- [x] `make build-mac` passes (Phase 1 — macOS toolbar path + shared row compile)
- [x] `make test-unit` passes (Phase 1 — new `removeChecklists` tests + `LocalizationTests` for the new `"Edit"` key; 237 tests / 33 suites)
- [x] `make test-ui` passes unchanged (Phase 1 — smoke identifiers still resolve; edit mode off at launch)
- [x] `make build` passes (Phase 2)
- [x] `make build-mac` passes (Phase 2)
- [x] `make test-unit` passes (Phase 2 — new `moveChecklists` tests + localization suites for `"Move up"` / `"Move down"`)
- [x] `make test-ui` passes unchanged (Phase 2 — no move control outside edit mode)
- [x] `bash scripts/test.sh` prints `gate: ok` (full gate: sim build → headless pre-boot → make test → build-mac → watch-build → 17/17 shell tests; run once after both phases)

## What landed

- **Phase 1** — `ChecklistStore.removeChecklists(at:)` (one whole-checklist tombstone
  per removal, single batched `save()`, no-op on empty/out-of-range), 6 XCTest store
  tests + `makeChecklistStore` fixture, `"Edit"` localization key (6 languages),
  edit mode on the main screen (`isEditing` state, `editToggleButton`, iOS header row
  / macOS toolbar item, per-row red minus with the existing confirmationDialog,
  navigation/run hidden while editing, exit edit mode when the store empties).
- **Phase 2** — `ChecklistStore.moveChecklists(from:to:)` (reuses `moved<T>`, no
  revision bump — top-level array order is the persisted order), 6 XCTest store tests
  incl. identity preservation across a reorder, `"Move up"` / `"Move down"` keys
  (6 languages), per-row chevron controls (disabled at row ends) as the trailing
  edit-mode element.

## Manual Verification Items (from the plan)

- [ ] `make run`, then: tapping **Edit** shows a red minus on each row, hides each row's play button, and row taps no longer push the detail screen; the label reads **Done**
- [ ] Tapping a row's minus shows the "Remove Checklist" dialog; **Cancel** keeps the checklist; **Remove** deletes it and the remaining rows keep their order
- [ ] Removing the last checklist lands on the empty state and the toggle is gone; creating a checklist afterwards does not reopen in edit mode
- [ ] Previously created reminders in the Reminders app are untouched (this feature never deletes reminders)
- [ ] On macOS (`make build-mac-signed` + run): the Edit item appears in the title bar next to create/settings and behaves identically
- [ ] `make run`: in edit mode each row shows chevrons; the first row's up and the last row's down are disabled/dimmed
- [ ] Tapping down on the first row swaps it with the second and the rows animate; the buttons re-disable at the new ends
- [ ] The new order survives relaunch (`make run` again) and the row that moved keeps its items and its detail screen
- [ ] Non-editing state is visually unchanged from before this ticket: plated card, floating create/settings plates, per-row play button

## Notes / observations for review

- The mandated `git rebase origin/main` rewrote the ticket's baseline start commit
  (`94a1935` → `6808ca2`), so the Phase 1 push was non-fast-forward; the remote
  baseline was stale, the branch is dedicated to this ticket, and the diff was a
  clean replay, so it was pushed with `--force-with-lease` after escalation.
  Phase 2 pushed fast-forward — no further divergence.
- `DELETEME` placeholder is untouched, left for the merge step per the start commit.
- The worktree simulator (`make test-ui`, gate pre-boot) was booted headlessly and
  left running; the full gate's EXIT trap manages shutdown on its next run.
- One test-authoring bug surfaced and was fixed within the phase (wrong move
  destination in `testMoveChecklistsPreservesChecklistIdentity`).
- Host data volume ran near-full (~121 Mi free) during one test-unit run — cosmetic
  xcodebuild log-archive warning only; all checks passed on rerun.