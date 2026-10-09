# Implementation Summary

Ticket: VAR-1120 — export folders
Branch: `alanvardy-var-1120-export-folders`

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | d618e7f | Walking skeleton — export/reimport reconstructs folder membership end to end |
| 2     | cf3e22f | Conflict decisions carry folder membership |
| 3     | 323a1c6 | Hardening — orphans, collapse state, ignored tombstones, collisions |

All three commits pushed to `origin/alanvardy-var-1120-export-folders`.

## Automated Checks
- [x] Phase 1: `make test-unit` — passed (608 tests in 67 suites)
- [x] Phase 1: `make build` — BUILD SUCCEEDED (app target, warnings-as-errors)
- [x] Phase 2: `make test-unit` — passed (612 tests in 67 suites)
- [x] Phase 3: `make test-unit` — passed (618 tests in 67 suites)
- [x] Phase 3: `./scripts/test.sh` — `gate: ok` (simulator build → pre-boot → `make test` → `build-mac` → `watch-build` → `scripts/tests/run.sh` → `shellcheck`; warnings-as-errors)

## Manual Verification Items (from the plan)
- [ ] Phase 1 — Simulator (`make run`): create a folder "Groceries", move a checklist into it,
      select that checklist, Export → open the JSON and confirm `"folders"` contains "Groceries"
      and `"folderTombstones"` is `[]`.
- [ ] Phase 3 (optional) — on a fresh simulator install, import a folder-bearing export → the
      imported checklist appears under a folder of the same name; import the same file again →
      still one folder.

Phase 2 added no manual items beyond Phase 1.

## Observations / Deviations from the plan
- **Plan wording (Phase 1 test).** The Phase 1 test `reImportingTheSameFileDoesNotDuplicateFolder`
  originally asserted that both member checklists point at one folder. Under Phase-1-only code
  `decide(.keepBoth)` does not forward a folder (that is Phase 2 Changes 2), so the assertion could
  not pass yet. The Phase 1 test was scoped to folder-count idempotency, and the survivor-folder
  assertion was added in Phase 2 once `.keepBoth` became folder-aware. No plan intent lost.
- **Phase 2 scope extension (needed for a Phase 2 test).** Implementing the plan's
  `keepExistingLeavesLocalFoldersUntouched` required narrowing `commit`'s folder pre-resolution to
  non-conflict candidates. The Phase 1 `commit` pre-minted folders for every selected candidate
  including pending conflicts, which would have minted the file's folder even when the user chose
  Keep Existing. Folders are now resolved/applied only for inserted candidates; conflict decisions
  remain the authority for conflicting candidates. Consistent with the plan's deviation note that
  `commit` builds `folderMap` for *selected* candidates only.

## Not changed (per plan)
No `Localizable.xcstrings`, no schema/version change, no `ChecklistMerge` /
`ChecklistSyncCoordinator` / Watch changes. `.pi/orksorksorks/` artifacts left uncommitted
(parent-owned).
