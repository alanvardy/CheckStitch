# Implementation Summary

All four phases of the plan were implemented, each delegated to a subagent,
verified, committed and pushed — one commit per phase.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `f13f59f` | Run Checklist intent walking skeleton (Core `ReminderAccessStatus` + `: Sendable`, `accessStatus()`, `ChecklistEntity`/query, `RunChecklistIntent` + dialogue, `CheckStitchShortcuts` provider, 6 catalog keys ×6 languages, spy/helpers, two test suites; spike confirmed App Intents metadata extraction so the shortcuts provider was kept) |
| 2     | `0999034` | Report partial creation exactly (`partiallyCreated(created,total,reason)` outcome + `errorMessage`, count-aware catch in `ChecklistReminders`, `ContentView` switch arm, intent dialogue arm, 7th catalog key, two `ChecklistRemindersTests` + one intent test) |
| 3     | `35fb150` | List My Checklists intent (`ListChecklistsIntent` + dialogue, second `AppShortcut`, 2 catalog keys ×6 languages, `ListChecklistsIntentTests` suite) |
| 4     | `459be21` | Hardening (5 new tests: fresh-store-per-perform, denied→granted, denial oscillation, long-name intactness ×2; all nine keys catalogued; full gate green) |

Plus a preparatory housekeeping commit `fe1a60f` dropping the `DELETEME`
placeholder the start commit had re-added.

## Automated Checks

- [x] `make test-unit` passes — 259 tests in 36 suites (incl. new `RunChecklistIntentTests` 10, `ChecklistEntityQueryTests` 5, `ListChecklistsIntentTests` 4; 13 existing `ChecklistRemindersTests` stay green)
- [x] `make build` succeeds (simulator; App Intents metadata extraction ran — `Metadata.appintents` present in `Debug-iphonesimulator/CheckStitch.app`)
- [x] `make build-mac` succeeds and `DerivedData/Build/Products/Debug/CheckStitch.app/Contents/Resources` contains the App Intents metadata (`ExtractAppIntentsMetadata` step in the log)
- [x] `make watch-build` succeeds — watch target does not compile `CheckStitch/Intents/` (target sources listed explicitly in `project.pbxproj`)
- [x] `make build` after Phase 2 — every `switch` over `ReminderRunOutcome` exhaustive (`ContentView`, `ChecklistReminders`, `RunChecklistDialogue`)
- [x] `rg -n "case .destinationMissing"` — both consumer call sites updated (`ContentView.swift:390` combined arm; intent dialogue) plus the Core `errorMessage`
- [x] `bash scripts/tests/run.sh` passes — 17 shell tests, unchanged
- [x] `bash scripts/test.sh` prints `gate: ok` (build → headless sim boot → test → build-mac → watch-build → shell tests → shellcheck)

## Manual Verification Items (from the plan)

- [ ] `make build-mac-signed`; open the macOS app; both `Run Checklist` and `List My Checklists` appear in Shortcuts.app
- [ ] Say "Run Groceries in CheckStitch"; the non-blank items appear in the checklist's destination Reminders list, with title/notes/due date mapped; Siri says the count
- [ ] Delete the destination list in Reminders, ask again → "That list no longer exists…"
- [ ] Reset Reminders permission (never asked) → the "open CheckStitch…" line, and **no prompt** appears
- [ ] Delete the destination list from Reminders *while* a multi-item run is in flight (or simulate with the spy) → Siri says "Created N of M …"; the in-app alert shows the counts + reason
- [ ] Both phrases resolve in Shortcuts.app and via Siri
- [ ] "List my checklists in CheckStitch" answers the names in app order; with none saved, the empty-state line; the app does not open
- [ ] `make build-mac-signed` + `bash scripts/run-devices.sh` (or the signed macOS build): install the bundle, confirm both actions in Shortcuts.app, run one spoken checklist end-to-end and confirm the reminders appear with titles/notes/due dates, and confirm the not-determined path produces no prompt
- [ ] State in the completion artifact what the user should see for the permission and partial-create paths

## Notes / Observations (out of plan scope, not changed)

- **Metadata spike confirmed**: the throwaway `SpikeIntent` produced `Metadata.appintents` in both simulator and macOS products, so `CheckStitchShortcuts.swift` was retained (design decision 9 not triggered).
- **`ChecklistEntityQueryTests` needed `@MainActor`** beyond the plan's annotation (store/query are app-target MainActor-isolated; the test target sets no default isolation). Necessary compile-time adaptation, no scope change.
- **Plan's `AppShortcut(...)` snippet had a pseudo-comma** between result-builder components (`@AppShortcutsBuilder` uses newline separation); removed.
- **Phase 2 verification wording** said `ChecklistReminders` is a "call site" of `case .destinationMissing` — it *returns* `.destinationMissing` rather than switching on it; the two real outcome-switches (ContentView, intent dialogue) are exhaustive, confirmed by the build.
- ~~`RunChecklistDialogue.message` placeholder~~ Phase 1 deleted the `.partiallyCreated` placeholder arm (enum case did not exist yet); Phase 2 added the real arm, as the plan required.
- Periphery/CI note: run `periphery` before merging if desired; no unused-code findings were introduced per the gate's build legs.