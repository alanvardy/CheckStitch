# Task

Add a settings toggle that prefixes each created Reminders reminder's title with its 1-based position, e.g. `1: Buy milk`, `2: Call the plumber`. Default off (no prefix), so current behaviour and existing tests stay unchanged.

Where things go (the ticket prescribes this):
- The preference is a new `@AppStorage`-backed property on `CheckStitch/ContentView.swift`, joining the existing keys (`appearanceMode`, `backgroundEnabled`, `backgroundFadePercent`, …), staged in `CheckStitch/SettingsBindings.swift` (the Settings-sheet snapshot + write-back already wired up in `ContentView`), and exposed as a new row in `CheckStitch/SettingsView.swift` with an `.accessibilityIdentifier("settings…Row")` like the existing rows.
- The numbering policy lives exactly once in `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift` — the policy seam that already drops blank titles and owns reminder creation for both paths (`CheckStitch/ChecklistReminders.swift` used by `ContentView` and the phone-sync coordinator in `MyApp.swift`, and the EventKit adapter behind `ReminderCreating`). Do not duplicate the numbering in any adapter.
- Both creation paths must honour the setting.

Required behaviour:
- Numbering is assigned *after* blank items are dropped, so an emptied row never leaves a gap — item one is always `1:`.
- Prefix format is `"<position>: "` (`1: Buy milk`); numbering is unbounded past 9 (`10: …`).
- Default off; the setting persists/syncs like the other `@AppStorage` keys (App Group suite / KVS behaviour).

Tests — add the four cases to the existing suites, following the `ChecklistCreatorTests` / `AppearanceModePreferenceTests` patterns:
- prefix off (default, no prefix added);
- prefix on;
- blank rows skipped without a gap;
- numbering past 9.

Verify with `make test-unit` before the full `bash scripts/test.sh` gate.

## Why MEDIUM
MULTI_MODULE (trigger 7): the change spans the app target (ContentView.swift, SettingsBindings.swift, SettingsView.swift, ChecklistReminders.swift) and CheckStitchCore (ChecklistCreator.swift) plus test suites — >5 files across two modules. M1/M2 hold: the approach is fully prescribed with an existing pattern (the `appearanceMode` preference and the existing Core policy seam) carrying the change end to end — no schema/migration, no new subsystem, no design decision or human sign-off.

## Key files
- `CheckStitch/ContentView.swift` — `@AppStorage("…")` key declarations (lines ~11–17); add the new key + any write-back wiring for the settings bag.
- `CheckStitch/SettingsBindings.swift` — staged-preference snapshot; add a `Bool` field (and stage it from the ContentView key).
- `CheckStitch/SettingsView.swift` — rows with `.accessibilityIdentifier("settings…Row")`; add the new toggle row bound to the binding.
- `CheckStitchCore/Sources/CheckStitchCore/ChecklistCreator.swift` — the policy seam; already drops blank titles; add the numbering policy here (consult the struct's `Sendable`-in-motion state, there may be an existing `Bool`/enum input pattern on `ChecklistCreating`-style config).
- `CheckStitch/ChecklistReminders.swift` — thin app-side creator; confirm it passes config straight to `ChecklistCreator` (no adapter duplication).
- `CheckStitchTests/ChecklistCreatorTests.swift`, `CheckStitchTests/AppearanceModePreferenceTests.swift` — homes for the four test cases; check `CheckStitchTests/TestFixtures.swift` for the reminder fakes.