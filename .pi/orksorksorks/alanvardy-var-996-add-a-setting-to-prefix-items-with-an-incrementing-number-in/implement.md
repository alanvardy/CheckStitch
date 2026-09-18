# Implementation Summary

Ticket: alanvardy-var-996 — add a setting to prefix items with an incrementing number in created reminders.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | c862158 | Numbering policy in Core (walking skeleton) |
| 2     | 7019819 | Production creation path honours the setting |
| 3     | 0d6c9ab | Settings-sheet toggle |

## Automated Checks

- [x] Phase 1 — `make test-unit` passes (all `ChecklistCreatorTests`, old and new)
- [x] Phase 1 — `make build-mac` passes (Core compiles cross-platform)
- [x] Phase 2 — `make test-unit` passes (existing `ChecklistRemindersTests` unchanged, new cases green)
- [x] Phase 2 — `make build` passes (app target compiles with the new key and call sites)
- [x] Phase 3 — `make test-unit` passes (all `SettingsBindingsTests`, old and new assertions)
- [x] Phase 3 — `make build` passes (SettingsView compiles with the new Section)
- [x] Phase 3 — Full gate `bash scripts/test.sh` prints `gate: ok` (run once by the parent after all phases committed)

## Manual Verification Items (from the plan)

- [ ] Phase 1 — `spy.createdTitles` in the four new cases shows exactly `1:`, `2:`, … with no gaps and no prefix when off.
- [ ] Phase 2 — `defaults write app.alanvardy.CheckStitch prefixReminderNumbers -bool true` then a checklist run creates `1: …`, `2: …` reminders (and off still creates plain titles).
- [ ] Phase 3 — Open Settings from the gear button → the "Number Reminders" row is present, off by default; toggling it on, running a checklist gives `1: …` titles, and the value survives relaunch (reopening Settings shows it still on).