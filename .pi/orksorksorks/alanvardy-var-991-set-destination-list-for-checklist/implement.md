# Implementation Summary

Branch `alanvardy-var-991-set-destination-list-for-checklist` — persist an optional
`destinationListIdentifier` on `Checklist`, make it first-class across codec/store/merge,
rework the run path into a pre-validating, outcome-returning orchestrator on an injectable
EventKit seam, and surface the selector + run failures in the UI.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| prep  | `db6d066` | chore: remove ticket scaffold placeholder (`DELETEME`) |
| 1     | `9979c86` | Model + codec — persist the destination field |
| 2     | `b9dc7e9` | Store mutation — `setDestination` |
| 3     | `28acfd6` | Merge — destination follows the checklist winner |
| 4     | `524eecd` | Run orchestration seam — pre-validate, then create-or-fail |
| 5     | `57a455b` | Real EventKit adapter |
| 6     | `7cc15fb` | Detail-screen destination selector |
| 7     | `c03b9fa` | Run-failure surfacing on the list screen |

All commits pushed to `origin/alanvardy-var-991-set-destination-list-for-checklist`
(plain fast-forward; one `--force-with-lease` on the very first push required by the
step-mandated `git rebase origin/main`, which rewrote the branch's own scaffold commit —
no foreign commits were present on the ticket branch).

## Automated Checks

- [x] Phase 1 — `make test-unit` passes (codec round-trip + v2-without-field→nil + watch transport)
- [x] Phase 2 — `make test-unit` passes (set/clear/nil-to-default + not-found sad path)
- [x] Phase 3 — `make test-unit` passes (winner/loser destination overwrite/preserve)
- [x] Phase 4 — `make test-unit` passes (7 run outcomes + message mapping; verified jointly with Phase 5)
- [x] Phase 5 — `make test-unit` passes (139 tests, 26 suites); `make build-mac` passes
- [x] Phase 6 — `make test-unit` passes; `make test-ui` passes (UI smoke)
- [x] Phase 7 — `make test-unit` passes; `make test-ui` passes (UI smoke)

## Manual Verification Items (from the plan)

- [ ] Phase 1 — `git grep -n destinationListIdentifier CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` shows exactly the init/property/key/decode/encode sites
- [ ] Phase 4 — `git grep -n "createdListIDs" CheckStitchTests/ChecklistRemindersTests.swift` shows the zero-create assertion in `missingDestinationCreatesNothing`
- [ ] Phase 5 — `make run` → open a checklist → run one with an explicit list → confirm in Reminders.app the reminder landed in that list (validates `calendarIdentifier` stability on this toolchain)
- [ ] Phase 5 — in Reminders.app, rename that list, then run again → the reminder still lands in the renamed list (identifier, not title, is the identity)
- [ ] Phase 6 — `make run` → edit a checklist → pick a non-default list → Done → relaunch → the picker still shows that list and it is checked in Reminders.app
- [ ] Phase 6 — `make run` → pick "Default (Inbox)" → run → the reminder lands in the default list
- [ ] Phase 6 — deny Reminders access in Settings → reopen the edit screen → only "Default (Inbox)" plus the explanatory note is shown
- [ ] Phase 7 — `make run` → pick a list for a checklist → delete that list in Reminders.app → run the checklist → the alert appears and Reminders.app shows zero new reminders (no green checkmark)
- [ ] Phase 7 — deny Reminders access → run a checklist → the permission alert appears, no green checkmark
- [ ] Phase 7 — happy path: valid list → run → green checkmark still flashes as before

## Notes / Observations

- **Inter-phase verification (Phases 4→5)**: Phase 4's `make test-unit` cannot pass in
  isolation because `make test-unit` compiles the `CheckStitch` app target and Phase 4's
  `ChecklistReminders.swift` references `EventKitReminderDestination.shared`, which Phase 5
  creates. This is the plan's own forward reference, not a divergence. Phase 4's code was
  committed as its own commit; Phase 5's green `make test-unit` run (139 tests) is the
  combined verification, and Phase 4's plan.md checkbox was flipped in the Phase 5 commit.
- **Full gate pending**: `./scripts/test.sh` (make build → sim pre-boot → make test →
  make build-mac → make watch-build → scripts/tests/run.sh → shellcheck) must print
  `gate: ok` before merge. Per the implement step it belongs to the review step, not this
  one — run it before declaring the work done.
- **Residual risks (accepted, from plan)**: `EKCalendar.calendarIdentifier` stability is
  assumed from the SDK (Phase 5 manual checks confirm; title-based identity is the fallback,
  not implemented). Merge winner-takes-all can point a checklist at a list absent on another
  device — that device's next run returns `.destinationMissing` and surfaces the alert.
- No phase required codebase adaptation beyond the plan's snippets; no pre-existing test
  flakiness encountered.
