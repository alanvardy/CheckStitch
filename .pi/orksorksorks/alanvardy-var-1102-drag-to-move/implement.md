# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | 534ce2b | Checklist drag-reorder (walking skeleton) |
| 2     | 65cdbc1 | Folder drag-reorder |

## Automated Checks
- [x] `make test-unit` (Phase 1 + Phase 2) — 480 then 485 tests, all passing
- [x] `make build` (iOS simulator, warnings-as-errors) — passed both phases
- [x] `make build-mac` (macOS slice) — passed both phases
- [x] `bash scripts/test.sh` printed `gate: ok` (Phase 2; covers make build/test/build-mac/watch-build, scripts/tests/run.sh, shellcheck)

## Manual Verification Items (from the plan)

Phase 1 — Checklist drag-reorder:
- [ ] `make run`; tap Edit; long-press a checklist row and drag it over another row in the same folder — the dragged row takes that slot and the order survives relaunch.
- [ ] In edit mode, drag a loose checklist over a folder member (and vice versa) — both sections are unchanged (cross-section no-op).
- [ ] In edit mode, drag the first loose row past the last loose row — it lands last (boundary).
- [ ] Leave edit mode: tapping a row still pushes the detail screen, and the remove/folder/chevron controls are gone.

Phase 2 — Folder drag-reorder:
- [ ] `make run`; tap Edit; drag a folder header over another folder header — the folder takes that slot and the order survives relaunch.
- [ ] Drag a collapsed folder's header — it reorders without expanding.
- [ ] Drag a checklist row over a folder header (and a folder header over a checklist row) — no reorder occurs in either direction.
- [ ] The chevron up/down nudges and the "Move to Folder" menu still work.