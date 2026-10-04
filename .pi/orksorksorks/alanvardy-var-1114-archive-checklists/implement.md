# Implementation Summary

Archive bookkeeping for `Checklist` — two additive optional fields
(`isArchived`/`archivedAt`, no codec version bump), a `ChecklistStore`
chokepoint (`archive`/`restore`/`removeArchived` + `activeChecklists`/
`archivedChecklists` filters), archive-aware merge + uniqueness, and a Settings
**Archived Checklists** subscreen. Archived checklists disappear from every
run/list surface (phone, watch, export, Siri/App Intents, widgets) but never
touch Reminders.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `5a50cb7` | Walking skeleton for archiving checklists |
| 2     | `ee8e492` | Archive state converges through the coarse-clock merge |
| 3     | `8bd80be` | Archived checklists screen with restore |
| 4     | `deef41b` | Permanent delete from the archived screen |
| 5     | `6ebb9b3` | Archived checklists invisible on watch, export, app intents, and widgets |
| 6     | `07c285a` | Imports land active with hardening |

Each commit was verified scoped: it contains only its phase's source/test files;
`plan.md`, `implement.md`, and the `.pi/orksorksorks/` directory were never
staged, and the unrelated governed scratch file `DELETEME` was left untouched.

## Automated Checks

- [x] `bash scripts/l10n-check.sh` → `l10n-check: ok` (4 catalogs, 166 keys, 6 languages)
- [x] `make test-unit` → 558 tests in 66 suites pass (incl. all new archive tests)
- [x] `make build-mac` → BUILD SUCCEEDED (new `ArchivedChecklistsView` compiles on macOS)
- [x] `make watch-build` → BUILD SUCCEEDED (watchOS slice)
- [x] `make widget-build` → BUILD SUCCEEDED (widget slice)
- [x] `bash scripts/test.sh` → `gate: ok` (full release gate, Phase 6)

All 8 new Phase 1 tests, 5 Phase 2 merge tests, 5 Phase 3 store tests, 3 Phase 4
tests, 11 Phase 5 tests, and 3 Phase 6 tests pass.

## Manual Verification Items (from the plan)

- [ ] **Phase 1**: `make run`; create a checklist, open it, Archive from the overflow menu, confirm; it leaves the main list; kill and relaunch the app; it is still gone. Confirm no Reminders were created/deleted.
- [ ] **Phase 2**: not manually reproducible without two devices; rely on unit evidence.
- [ ] **Phase 3**: `make run`; archive two checklists; Settings → Archived Checklists lists both newest-first; swipe Restore pops one back to the main list with its items intact; archive "X" + create active "X", restore → appears as "X 2".
- [ ] **Phase 4**: `make run`; archive a checklist, swipe Delete Permanently, confirm; it is gone from the Archived screen after relaunch and a merge; no Reminders touched.
- [ ] **Phase 5**: not device-verifiable here; the gate's watch/widget builds plus unit evidence are the proof.
- [ ] **Phase 6**: n/a (full gate).

## Notes / Deviations

- **Phase 3 `restore(id:)`** — the plan's literal `taken: activeNames.filter { $0 != checklists[index].name }` was incorrect for the collision case: `activeNames` already excludes the still-archived target, so the filter stripped the *live collider's* exact name from `taken` and `uniqueName` returned the colliding name unchanged instead of the mandated `"Groceries 2"`. Implemented as `taken: activeNames`, which satisfies the plan's intent and the mandated `testRestoreAutoRenamesOnActiveCollision`.
- **`ChecklistExportTests.swift`** (plan deviation #4) — inspected during Phase 6; its assertions read only fixture arrays and never `store.checklists`, so it was left untouched.