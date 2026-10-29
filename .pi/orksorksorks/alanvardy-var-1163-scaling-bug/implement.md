# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `e5ab1bd` | Phase 1: resolver strips markers at every multiplier |
| 2 | `5bae6bc` | Phase 2: run-path regression lock for factor 1 |
| 3 | — (no commit) | Phase 3 is audit-only: no production or test changes; full gate run |

All commits are pushed to `origin/alanvardy-var-1163-scaling-bug`.

## Phase detail

- **Phase 1** (`CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift`,
  `CheckStitchTests/ChecklistCreatorTests.swift`): the sole defect — the
  `multiple != 1` short-circuit in `ChecklistScaling.resolve` — was replaced
  with `guard text.contains("((")`, and the doc comment now states markers
  resolve at every multiplier including `1`. Resolver body below the guard is
  byte-identical. `multipleOneIsAFastPath` was deleted and replaced by
  `markersResolveAtOne`. The default-1 caller audit found no test asserting
  literal brackets at default `multiple` (all marker cases pass explicit
  multiples), so no further test edit was needed.
- **Phase 2** (`CheckStitchTests/ChecklistRemindersTests.swift`,
  `CheckStitchTests/ChecklistRunViewModelTests.swift`,
  `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`): added
  `fixedOneStripsMarkersOnRun` (`.fixed(1)` run emits `"1: milk 2"` / `"4 boxes"`)
  and `promptConfirmedAtOneStripsMarkers` (prompt confirmed at `1` emits
  `"milk 2"` and is never persisted); reworded only the `displayNumber` doc
  comment (no value/API change).
- **Phase 3**: audit-only, no edits. Confirmed no preview call site needs a
  mode branch (`ChecklistDetailView` resolves via `scaling.number`,
  `WatchChecklistDetailView` via `scaling.displayNumber`, neither special-cases
  prompt/literal brackets); help text and all six translations already say "The
  brackets are removed" with no `Localizable.xcstrings` /
  `LocalizationFixtures.swift` change; `RunChecklistIntent` delegates to
  `ChecklistReminders.create` and inherits the corrected contract untouched.

## Automated Checks

- [x] `make test-unit` passes (690 tests in 71 suites) — Phase 1 and Phase 2
- [x] `markersResolveAtOne` present (exactly 1 hit); `multipleOneIsAFastPath` gone (0 hits)
- [x] `make build` passes with warnings-as-errors — Phase 1 and Phase 2
- [x] Default-1 caller audit: no test relies on literal brackets at default multiple
- [x] `fixedOneStripsMarkersOnRun` and `promptConfirmedAtOneStripsMarkers` both present
- [x] Existing pins still green and unchanged: `runningDoesNotRewriteStoredItemText`, `displayNumberIsNeutralForPrompt`, `createRemindersForwardsTheOverrideWithoutPersisting`
- [x] `git diff` on `Checklist.swift` shows only comment lines changed
- [x] `./scripts/test.sh` prints `gate: ok` (build → simulator pre-boot → test → build-mac → watch-build → shell tests → shellcheck)
- [x] `rg -n 'displayNumber'` confirms Watch preview still uses `displayNumber`, value unchanged
- [x] `git status` shows no changes under `CheckStitch/Localizable.xcstrings` or `CheckStitchTests/LocalizationFixtures.swift`

## Manual Verification Items (from the plan)

- [ ] Phase 1: Confirm the resolver body below the guard is byte-identical to the
      previous implementation (`git diff` shows only the guard line, the doc
      comment, and the test file).
- [ ] Phase 2: `git diff CheckStitchCore/Sources/CheckStitchCore/Checklist.swift`
      shows only the comment lines changed — no switch arm or value change.
- [ ] Phase 3: `make run`; open a checklist whose item title is `((2))` at factor
      1 (or set scaling to 1 / confirm the prompt with 1), run it, and confirm the
      created reminder reads `2` (no literal brackets), while the checklist's
      stored item text still shows `((2))`.
- [ ] Phase 3: Eyeball the app detail view for `.prompt` mode (renders at
      `lastFixed`) and the Watch detail preview (renders at `displayNumber == 1`)
      — both should show bracket-free text, the deliberate consequence recorded
      in `design.md`'s "Open Risks".

## Notes / observations

- The pre-existing deleted `DELETEME` placeholder and the untracked
  `.pi/orksorksorks/<branch>/` artifacts were deliberately left unstaged; no
  phase commit included them.
- Phase 3 produced no commit because it is explicitly audit-only (no production
  or test changes).
