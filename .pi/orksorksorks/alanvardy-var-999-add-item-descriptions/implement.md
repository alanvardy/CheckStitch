# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 0     | 9affb23 | Rebase on origin/main (prerequisite) |
| 1     | 34aa54f | Model & codec — the schema layer |
| 2     | 226792d | Store — description mutation & duplication |
| 3     | 20b25a1 | Sync & merge hardening — tests only |
| 4     | 136c8c3 | Reminder destination seam — description → EKReminder.notes |
| 5     | eb77377 | iOS editor — per-row description field |
| 6     | a1d6d6e | watchOS row — secondary caption line |

All pushed to `origin/alanvardy-var-999-add-item-descriptions` (history force-updated
once in Phase 0 to the rebased base, then fast-forwarded per phase).

## Automated Checks

- [x] `git rev-list --count HEAD..origin/main` prints `0` after the Phase 0 rebase
- [x] `grep -n "currentVersion = 3"` matches; `ChecklistCodec.currentVersion` still `3` — no version bump
- [x] `make test-unit` green after every phase (baseline 168 tests → 179 at the end)
- [x] `make build` (simulator) passes — iOS body compiles with `TextField(axis: .vertical)`
- [x] `make build-mac` passes — protocol conformance and view compile on macOS
- [x] `make watch-build` passes — watchOS row compiles
- [x] `bash scripts/test.sh` prints `gate: ok` (sim build → headless pre-boot → `make test` → `make build-mac` → `make watch-build` → shell tests 17/17 → shellcheck)
- [x] `grep -rn "func create(title:"` — both `ReminderDestinationTargeting` conformances carry `notes: String?`; the legacy `ReminderCreating` seam keeps the old signature (intentional)
- [x] `grep -n '"Description"'` matches in both `CheckStitch/Localizable.xcstrings` and `CheckStitchTests/LocalizationFixtures.swift`
- [x] Legacy core `ChecklistCreator`/`ReminderCreating` untouched — no commits on this branch touch those files
- [x] New tests cover happy + sad paths: additive-codec decode (absent key → `""`, malformed value → `.unreadable`), store edit/reload/persist/no-op/duplicate, merge LWW winner + both-descriptions-survive, sync push/refresh round trip, watch transport round trip, notes forwarding (`notesForwardDescription`, `blankDescriptionSendsNilNotes`, `deniedAccessNeverSendsNotes`), render canary, localization six-language + fr exclusion

## Manual Verification Items (from the plan)

- [ ] Phase 0: `git log --oneline -1` shows the branch commit on top of `origin/main` — note the replay commit's hash changed to `7472392` after the rebase (was `b37addd` pre-rebase)
- [ ] Phase 1: Inspect encoded JSON for one item — confirm a `"description"` key is present and the `currentVersion` file line is still `3`
- [ ] Phase 2: `grep -n "updateItemDescription" CheckStitch/ChecklistStore.swift` shows the new mutator; `updateItem`/`addItem` unchanged
- [ ] Phase 3: `git diff --name-only` for the stage lists only `CheckStitchTests/` files
- [ ] Phase 4: `grep -n "ChecklistCreator" CheckStitch/ContentView.swift CheckStitch/MyApp.swift` shows no production call site
- [ ] Phase 5: `make run` on the simulator — open a checklist; each row shows a title field and a smaller multiline description field; typing a description does not disturb the title; the description persists after leaving and re-entering the screen (and after app relaunch)
- [ ] Phase 6: `bash scripts/run-watch.sh` on the paired watch — a described item shows the title plus a secondary caption; an item with no description shows only the title
- [ ] Phase 6: a blank-title item with a populated description stays hidden (still filtered by `isBlank`)
- [ ] Phase 6: a long description is clamped by SwiftUI's line limit without breaking the row

## Final checklist

- [x] `make test-unit` green after every stage
- [x] `bash scripts/test.sh` prints `gate: ok`
- [x] No `currentVersion` bump; `ChecklistCodec.currentVersion` is still `3`
- [x] Legacy core `ChecklistCreator`/`ReminderCreating` untouched
- [ ] PR description notes the accepted risk: an older v3 build silently drops `description` on its next save (inherent to an additive field without a version bump)

## Observations for Review

- The Phase 0 manual item's literal hash (`b37addd`) is stale post-rebase; the replayed commit is `7472392` with the same message.
- The Phase 4 literal grep also surfaces the legacy `ReminderCreating` `create(title:)` signatures (2 matches) — the meaningful reading ("only the two conformances with the new signature") holds for `ReminderDestinationTargeting`; the legacy seam is deliberately unchanged per the plan.
- Accepted risk for the PR description: an older v3 build of the app, running against a payload that now carries `description`, will silently drop the field on its next save (additive field without a version bump). This is inherent and was accepted in design.
- No production file was changed outside the plan's scope; no refactors performed.