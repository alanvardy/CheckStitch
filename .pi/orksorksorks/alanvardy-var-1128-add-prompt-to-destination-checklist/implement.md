# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 0 | `16ae506` | ChecklistDestination model + codec v6 |
| 1 | `308160b` | app prompt end to end |
| 2 | `7e10f21` | intent prompt for Siri and Shortcuts |
| 3 | `5fc0188` | widget prompt opens the app |
| 4 | `f62468f` | watch replies choose a list on iPhone |
| 5 | `41bcc9c` | hardening and edge states |

All six commits are pushed to
`origin/alanvardy-var-1128-add-prompt-to-destination-checklist`.

## Automated Checks
- [x] Phase 0: `make test-unit` green (625 tests), `make build` clean, no
      `destinationListIdentifier` compiler use remains (only the legacy decode
      fallback + `CodingKeys` in `Checklist.swift`), new v5/v6 codec tests and
      merge `.prompt`-winner/idempotence test pass.
- [x] Phase 1: `make test-unit` green (632 tests), `make build` clean,
      `bash scripts/l10n-check.sh` → `l10n-check: ok`, new funnel + run-VM tests
      pass.
- [x] Phase 2: `make test-unit` green (642 tests), `make build` clean,
      `l10n-check: ok (4 catalogs, 185 keys, 6 languages)`, new intent +
      `ReminderListEntityQuery` tests pass.
- [x] Phase 3: `make test-unit` green (647 tests), `make widget-build`
      succeeded (`** BUILD SUCCEEDED **`), new run-VM deep-link + widget-row
      `isPrompt` tests pass.
- [x] Phase 4: `make test-unit` green (648 tests), `make watch-build` and
      `make build` succeeded, wire round-trip / coordinator reply / watch phase
      tests pass.
- [x] Phase 5: `make test-unit` green (653 tests), `bash scripts/l10n-check.sh`
      → `l10n-check: ok`, full gate `./scripts/test.sh` printed `gate: ok`
      (sim build → headless sim pre-boot → sim test → build-mac → watch-build →
      26 shell tests → shellcheck).

## Notes / deviations
- **Phase 0 → Phase 1 compile bridges.** Adding
  `ReminderRunOutcome.destinationRequired` (Phase 1) made two switches in
  Phase-owned files non-exhaustive. Two minimal, temporary bridges were added
  and then superseded exactly as planned:
  - `ChecklistSync.RunResultKind.init(_ outcome:)`: `.destinationRequired → .failed`
    (replaced in Phase 4 with the real wire kind).
  - `RunChecklistIntent.message(for:checklistName:)`: `.destinationRequired → denied`
    (replaced in Phase 2 with the real `destinationRequired` dialogue).
- **Phase 3 child timed out** at the 30-minute harness limit after its
  `make test-unit` run (647 tests green) but before `make widget-build`,
  checkbox marking, and commit. The parent inspected the working-tree diff
  (matched the plan), ran `make widget-build` (`BUILD SUCCEEDED`), marked the
  Phase 3 automated checkboxes, and committed the finished work as `5fc0188`.
  The Phase 3 implementation also factored the deep-link parsing into a
  testable `ChecklistRunViewModel.destinationPromptChecklistID(from:)` static —
  an in-scope refinement of the plan's inline snippet.
- Phase 5 is test-only (5 test files, no production change).

## Manual Verification Items (from the plan)
- [ ] Phase 1: `make run`; open a checklist → Destination list → tap **Ask me
      each time**; back out; tap Run; the sheet lists every Reminders list plus
      **Default (Inbox)**; pick one, tap Run; reminder lands in that list;
      re-open the detail picker → still **Ask me each time**
- [ ] Phase 2: In Shortcuts, add **Run Checklist**, choose a `.prompt`
      checklist; the run shows the list picker; picking a list creates reminders
      there. Delete the parameter value and run from a non-UI context → the
      `.destinationRequired` dialog appears
- [ ] Phase 3: `make run`; add a widget for a `.prompt` checklist; tap the tile
      → app opens on the prompt sheet for that checklist; `checkstitch://` access
      prompts still work
- [ ] Phase 4: `bash scripts/run-watch.sh`; tap Run on a `.prompt` checklist on
      the Watch → the footer shows **Choose a list on iPhone.** and no reminders
      are created
- [ ] Phase 5: `make run`: revoke Reminders access → Run a prompt checklist →
      the permission-denied message appears, no empty sheet; restore access and
      confirm the prompt flow still works
- [ ] Phase 5: Confirm the app still builds with warnings-as-errors (gate covers
      this)
