# Implementation Summary

Branch: `alanvardy-var-969-create-and-delete-checklists-from-a-scrollable-list`
Rebased onto `origin/main` (`2dad2c3`, Sep 11 09:07) before any phase work.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `331d02d` | Model + App Group accessor (+ test target) |
| 2     | `c24a234` | Persistence store |
| 3     | `817724a` | Reminders service |
| 4     | `49cbcbd` | Detail screen |
| 5     | `9e9b172` | List screen + navigation wiring |

(Plus `0039b7c` "chore: record step artifacts…" and `2dad2c3` "chore: start…" at the base.)

## Automated Checks

- [x] `plutil -lint CheckStitch.xcodeproj/project.pbxproj` → `OK`
- [x] Hand-edited test target loads: `xcodebuild -list` shows `CheckStitch` and `CheckStitchTests` targets + `CheckStitch` scheme (no Xcode GUI fallback needed)
- [x] `make test` → `Executed 3 tests, with 0 failures` (Phase 1)
- [x] `make test` twice in a row → `Executed 9 tests, with 0 failures` both runs (no cross-run suite bleed, Phase 2)
- [x] `./scripts/test.sh` prints `gate: ok` after Phases 1, 2, 3, 4 and 5 (build + 9 unit tests + shellcheck)
- [x] `grep -rn "createChecklistReminders" CheckStitch/` → no matches (Phase 3; `Self.logger` in `ChecklistStore.swift` is the plan's own Phase 2 code — see deviations)
- [x] `grep -rn "EditChecklistView" CheckStitch/` → no matches (Phase 4)
- [x] `xcodebuild -list` after Phase 5 still shows the `CheckStitch` scheme
- [x] `git status` clean — no `DerivedData/` or `.simulator_id` changes; scripts remain mode `100755`

## Deviations & Observations (adaptations, none silent)

1. **The plan was written against a pre-main tree.** The design artifacts (09:00–09:05) predate main commits that landed this worktree via the rebase: the settings menu + appearance theme (`030a120`), the macOS build fix with app delegates (`c2ac389`), cross-platform `toolbarTitleDisplayMode` (`326b861`), and `ChecklistWidth` (`-972`). The plan's line numbers were stale throughout, and its Phase 5 "full rewrite" of `MyApp.swift`/`ContentView.swift` would have deleted those shipped features. Phases 4–5 therefore **merged** instead of blind-replaced: iOS/macOS app-delegate adaptors, `@AppStorage("appearanceMode")`, the Settings sheet/button, the appearance `.onChange` (both platforms) and the `ChecklistWidth` enum are all preserved.
2. **`ChecklistDetailView` uses `.toolbarTitleDisplayMode(.inline)`**, not the plan's iOS-only `.navigationBarTitleDisplayMode(.inline)`, to match the repo-standard cross-platform API (main `326b861`) and keep the macOS build green.
3. **Phase 3 plan gap:** deleting `createChecklistReminders()` left the create button calling a removed function. Interim fix (removed again in Phase 5): the button called `ChecklistReminders.create(from: Checklist(name: checklistName, items: items))` — byte-for-byte the old behavior.
4. **Phase 4 plan gap:** deleting the `EditChecklistView` struct required also deleting its `.sheet(...)` block (compilation). Per a supervisor decision, `@State isShowingEditChecklist` + `editChecklistButton` were kept as a temporarily dead affordance; Phase 5's rewrite removed them.
5. **`ChecklistReminders` uses the plan's bare `logger`** (not `Self.logger`); the only `Self.logger` left in the repo is `ChecklistStore.swift:74`, which is the plan's own Phase 2 code — the Phase 3 grep criterion as literally written in the plan is unreachable post-Phase 2, but its intent (no leftovers from the moved logic) is satisfied.
6. **`ChecklistWidth` is now unused** — its only caller was the old `GeometryReader` body the list screen replaced. Kept per -972 shipped code; a later ticket may delete it.
7. pbxproj test-target hand-edit landed with the plan's fixed object IDs and no plist-load problems; the committed shared scheme makes `xcodebuild test` deterministic.
8. **Review decision — the test target + gate change was kept and retro-documented**, not reverted: `AGENTS.md` (gate + Layout), `conventions.md` (Test-suite inventory) and `design.md` ("What We're NOT Doing") now record that the repo has a `CheckStitchTests` suite and the gate is `make build` + `make test` + shellcheck. This is a deliberate, documented widening of the gate's contract (VAR-969 review, option 1).

## Manual Verification Items (from the plan)

- [ ] **Phase 3** — `make run`, open a checklist with 3 named items, Create reminders → 3 reminders appear in the Reminders Inbox
- [ ] **Phase 3** — Add a blank item row, Create reminders → no reminder for the blank row, no crash
- [ ] **Phase 3** — Deny Reminders access (Settings → CheckStitch → Reminders → off), Create reminders → no reminders, no crash, no visible error (log only)
- [ ] **Phase 4** — `make run` → open a checklist, rename it, add items, edit item text, swipe-delete an item; `make run` again (relaunches) → all changes persisted
- [ ] **Phase 4** — Remove Checklist → the checklist disappears from the list **and** the screen pops (no "Checklist not found" left on screen)
- [ ] **Phase 4** — Create reminders for that checklist first, then Remove → reminders stay in Reminders
- [ ] **Phase 4** — Done (toolbar) → pops but the checklist is still in the list
- [ ] **Phase 5 (1)** — Create two checklists with distinct names and items, force-quit/relaunch → both reappear with names and items intact
- [ ] **Phase 5 (2)** — Create reminders from one checklist, see its row flash a spinner then a green checkmark, then Remove Checklist → the checklist is gone from the list and its reminders are still in Reminders
- [ ] **Phase 5 (3)** — Create a checklist → it is pushed immediately; edit name/items, relaunch → edits persist
- [ ] **Phase 5** — Optional device proof of real App Group sharing: `bash scripts/run-devices.sh`, create a checklist, relaunch on device → checklist persists
- [ ] **Phase 5 (4)** — `./scripts/test.sh` → `gate: ok` *(automated — already passing; listed as a manual item by the plan)*
- [ ] **Phase 5** — `git status` shows no `DerivedData/` or `.simulator_id` changes; scripts remain mode `100755` *(automated — already verified)*

## Checkpoint Notes (from plan "Testing Checkpoints")

- After Phase 1 / Phase 2 checkpoints are checked in `plan.md` (automated).
- After Phase 3 / 4 / 5 checkpoints stay unchecked — they are gated on the manual items above.