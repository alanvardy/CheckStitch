# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `5224ce9` | Create Checklist intent -> stored checklist |
| 2     | `31f58b1` | Backgrounded app folds in intent write |

(Note: an extra preparatory commit `be4fb61 chore: drop DELETEME placeholder` removed the worktree placeholder file so the required rebase could proceed.)

## Automated Checks
- [x] `bash scripts/l10n-check.sh` passes (4 new keys × 6 languages, non-English differs)
- [x] `make test-unit` passes (new store XCTest methods + `CreateChecklistIntentTests`)
- [x] `make build` compiles `@Parameter var items: [String]` (unknown (a) confirmed; no multiline-String fallback needed)
- [x] App Intents metadata contains `CreateChecklistIntent` (unknown (b) confirmed; intent stays in Core)
- [x] `make test-unit` passes (new reconcile methods + everything from Phase 1) — 584 tests / 67 suites
- [x] `./scripts/test.sh` prints `gate: ok` (adds `make build-mac`, `make watch-build`, shell checks — 26 shell tests)

## Manual Verification Items (from the plan)
- [ ] `make build-mac-signed`, open macOS Shortcuts.app, confirm a **Create Checklist** action exists with Name + Items (list) fields and summary "Create (Name) with (Items)"
- [ ] `make build-mac-signed` / `scripts/run-devices.sh`; in Shortcuts.app run Create Checklist while the app is backgrounded; return to the app and confirm the checklist is listed with its items and survives a subsequent edit. Re-run with a duplicate name (expect "… 2"), blank name (expect "Give the checklist a name."), and no items (expect "Add at least one item.")
- [ ] Confirm the created checklist reaches the watch/widget after returning to `.active`

## Notes / Observations
- The plan's whitespace store-test example `" groceries "` (lowercase) actually yields `"groceries 2"` (lowercase) because `uniqueName` preserves input case while trimming. The store test uses `"  Groceries  "` to assert the plan's literal `"Groceries 2"`, matching documented `uniqueName` behavior.
- Reconcile tests use `try!` around `ChecklistCodec.encode`, matching the effectively-infallible JSON encoding; existing suites sometimes prefer `try?`/`XCTUnwrap`.
- `reconcileFromDefaults()` handles only `.loaded` (current-version) payloads per spec; `defaults.synchronize()` is a cross-platform no-op nicety.