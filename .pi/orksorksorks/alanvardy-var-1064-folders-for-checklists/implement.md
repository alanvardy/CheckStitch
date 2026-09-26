# Implementation Summary

All 6 phases of the folders-for-checklists plan implemented on branch
`alanvardy-var-1064-folders-for-checklists`, one commit per phase, each pushed
to `origin`.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `2bfc6ed` | walking skeleton — folders end to end (Folder/FolderTombstone types, Checklist.folderID, codec v5 + `classify` case 4, store folder create/move, merge folder union + pruning, sync pass-through, VM grouping, ContentView folder-first render + move menu + create affordance) |
| 2     | `a46fe4b` | folder merge/sync correctness (test gate: 6 new `ChecklistMergeTests`) |
| 3     | `ef5fd96` | rename and reorder folders (edit mode) + App localization keys |
| 4     | `c00369a` | delete a folder, orphaning its checklists (tombstone + members back to loose) |
| 5     | `2e8204e` | watch shows folders as sections (Core grouping, phone→watch transport, Watch l10n) |
| 6     | `13b7f21` | hardening, states, localization (verification + gap-closing; added one grouping test) |

## Automated Checks

- [x] Phase 1: `make test-unit` passes (incl. mechanical v4→v5 codec/store updates)
- [x] Phase 1: `make build` passes under `WARNINGS_AS_ERRORS`
- [x] Phase 1: `bash scripts/l10n-check.sh` passes
- [x] Phase 2: `make test-unit` passes
- [x] Phase 2: `bash scripts/tests/run.sh` passes (shell gate, unchanged)
- [x] Phase 3: `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] Phase 3: `make test-unit` passes (incl. `LocalizationTests.everyRequiredKeyIsPresent`)
- [x] Phase 3: `make build` passes
- [x] Phase 4: `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] Phase 4: `make test-unit` passes
- [x] Phase 4: `make build` passes
- [x] Phase 5: `make test-unit` passes
- [x] Phase 5: `make watch-build` passes
- [x] Phase 5: `make build` passes
- [x] Phase 5: `bash scripts/l10n-check.sh` passes (including the Watch key)
- [x] Phase 6: `bash scripts/l10n-check.sh` prints `l10n-check: ok`
- [x] Phase 6: `make test-unit` passes
- [x] Phase 6: `make test-ui` passes
- [ ] Phase 6: `bash scripts/test.sh` prints `gate: ok` — **scoped to the review step** (full gate), not run in implement
- [ ] Phase 6: `make build-mac-signed` passes — **scoped to the review step** (needs provisioning profile)

## Manual Verification Items (from the plan)

- [ ] Phase 1: `make run`: enter edit mode → "New Folder" appears; create "Work"; a checklist row shows the folder menu; choosing "Work" renders a "Work" section with the checklist under it and the loose group below; relaunch the app and confirm it survived
- [ ] Phase 1: With no folders, the list looks exactly as before (no "Loose" header)
- [ ] Phase 2: Simulator A creates a folder + moves a checklist in; stop A, relaunch (or use a second simulator signed into the same App Group/iCloud) → the folder and membership converge and do not duplicate
- [ ] Phase 2: Delete the folder (after Phase 4) on one side → it stays gone after the other side re-syncs (no resurrection)
- [ ] Phase 3: `make run`: edit mode → a folder header shows pencil + up/down; rename opens the alert pre-filled; renaming to an existing name yields a " 2" suffix; chevrons reorder; relaunch preserves order
- [ ] Phase 3: Non-edit mode shows no folder controls
- [ ] Phase 4: `make run`: edit a folder → minus → confirm dialog → folder disappears and its checklists appear under "Loose"; relaunch preserves it
- [ ] Phase 4: Cancelling the dialog leaves the folder intact
- [ ] Phase 5: `bash scripts/run-watch.sh` (with the phone app running): the watch list shows the same folder names as sections and the loose group last; tapping a checklist still opens its detail view
- [ ] Phase 5: Renaming/reordering a folder on the phone updates the watch after the next context push
- [ ] Phase 6: `make run`: create folders, move checklists in/out, rename, reorder, delete — all persist across relaunch; an empty folder and an all-loose list render cleanly
- [ ] Phase 6: Real-device close-out (required for sync/UI tickets): `bash scripts/run-devices.sh` → the installed app shows folder sections on iPhone + host Mac, and moving/renaming/deleting a folder syncs to the second device and the paired watch; state what the user should see (folder header, members indented, "Loose" group)
- [ ] Phase 6: Watch: `bash scripts/run-watch.sh` shows the same sections

## Notes

- The Core `Localizable.xcstrings` catalog stayed **unchanged** — grouping is
  string-free; `ChecklistGrouping.sections` and the VM `checklists(in: nil)`
  both route an unknown `folderID` to loose, so cross-reference skew never
  drops a checklist.
- Two small deviations from the plan's literal snippets, both required by the
  actual codebase: the VM test file is named `ChecklistListViewModelTests.swift`
  (plan wrote `CheckList…`), and Swift-Testing tests use the postfix `!`
  unwrap (repo precedent) rather than `#require`. Phase 6 is a
  verification/gap-closing phase — its single source change is one new
  grouping test (`emptyFolderWithLooseMembersRendersLooseLast`).
- The full `./scripts/test.sh` gate and `make build-mac-signed` are deferred to
  the review step per the orchestration instructions.