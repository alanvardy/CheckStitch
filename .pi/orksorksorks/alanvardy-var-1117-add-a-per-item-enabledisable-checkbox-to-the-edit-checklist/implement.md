# Implementation Summary

Per-item `isEnabled` checkbox for the "Edit checklist" screen, synced and merged
as a per-field LWW clock, excluded from every run path (phone, watch, widget).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `3456083` | Walking skeleton — model + codec (isEnabled + clocks + predicates; mergedItems LWW + coarse high-water folded in for gate coherence) |
| 2     | `e0465f3` | Merge — LWW branch + coarse high-water (merge tests) |
| 3     | `66c4e83` | Store — toggle mutation (`updateItem(..., isEnabled:)`) |
| 4     | `ffdf368` | Run — exclude disabled items everywhere (`ChecklistReminders`, `ChecklistCreator`) |
| 5     | `10c57fb` | Localization key (`"Include in reminders"`, 6 languages + fixture) |
| 6     | `669d7a9` | Phone UI — checkbox, dimming, run gating |
| 7     | `1825b6e` | Watch + widget gating |

All pushed to `origin/alanvardy-var-1117-add-a-per-item-enabledisable-checkbox-to-the-edit-checklist`.

## Automated Checks

- [x] `make test-unit` passes across Phases 1–7 (running total 582 → 596 tests in 66 suites)
- [x] Envelope version stays `5`; disabled item codec round-trips; absent key decodes to `true`; encoded payload contains the three new keys
- [x] `isRunnable`/`hasRunnableItems` predicates cover disabled/blank/enabled and `[]`/all-blank/all-disabled/one-enabled
- [x] `isEnabled` merge: newest enabledRevision wins, older does not leak, coarse high-water covers adopted enabled clock
- [x] Store toggle stamps `enabledRevision == revision`, `enabledModifiedAt == modifiedAt`, bumps revision; unchanged value no-ops; unknown ids silent; item op never bumps checklist clock; newly-added item enabled by default
- [x] Run path skips disabled items (no reminder, contiguous numbering `1, 2`, totals count only runnable); all-disabled returns `created(count: 0)` and releases the run slot
- [x] `bash scripts/l10n-check.sh` passes; LocalizationTests required-keys check passes
- [x] `make build` (simulator) succeeds
- [x] `make watch-build` succeeds
- [x] Phase 6 run VM: proceeds with ≥1 runnable item; silent no-op when all disabled or blank
- [x] Widget model: ready + zero enabled ↦ `isRunnable == false`; adding one toggles to `true`; access gate still dominates
- [x] `bash scripts/test.sh` prints `gate: ok` (Phase 8) — full gate green
- [x] `git status` clean of stray `.pi/orksorksorks/` artifacts; one commit per phase

## Deviations (reviewers, please note)

1. **Phase 1 folded the Phase 2 merge block.** Adding the new field clock without the
   `mergedItems` branch broke three existing argument-order-independence merge tests.
   Per supervisor decision, the full Phase 2 `mergedItems` change (isEnabled LWW branch +
   coarse high-water `enabledRevision`) was folded into the Phase 1 commit so the model
   stayed internally consistent and Phase 1's own `make test-unit` gate was green.
   Phase 2's remaining work (merge tests) landed separately as its own commit.
2. **Watch `visibleItems` has no dedicated unit test (plan bullet left unchecked).**
   `WatchChecklistViewModel` lives in the watchOS target (`CheckStitchWatch/`), which is
   excluded from the macOS-hosted `CheckStitchTests` build (it links `CheckStitchCore` +
   phone app only). `@testable import CheckStitchWatch` is unavailable. Per supervisor
   decision (Option B) the filter stayed on the VM — the plan's `WatchChecklistStoreTests`
   bullet was named against a mistaken assumption; predicate semantics are covered by the
   core `ChecklistItemTests`/`Checklist.hasRunnableItems` cases, and the watch's visible
   behavior is a Manual item. plan.md bullet `:480` left unchecked with an inline note.
3. The test fixture factory is `makeItem(...)` (not the plan's `ChecklistItem(title:description:)`
   name); adapted to the real code with an `isEnabled` parameter.

## Manual Verification Items (from the plan)

- [ ] Build/run, open "Edit checklist": every item row has a leading circle; tapping the circle toggles to a filled check and dims the row (title + description secondary, no strikethrough); tapping the rest of the row still pushes "Edit item"
- [ ] Uncheck every item: the row's run button becomes disabled; re-check one and it re-enables
- [ ] Watch: a checklist whose items are all disabled shows no rows and a disabled run button; a single enabled item restores both
- [ ] Widget: a fully-disabled checklist shows the run control disabled