# Task

Add a "Select All" button to the export checklists screen so a user can select
every checklist at once before exporting. Today the export sheet requires
tapping each row individually; importing a long list one-by-one is tedious.

The export sheet (`CheckStitch/ExportChecklistsView.swift`) is a thin wrapper
over the shared multi-select sheet
(`CheckStitch/ChecklistSelectionView.swift`), which is also used by the Import
sheet in `CheckStitch/ContentView.swift`. Follow the existing optional-second-
action precedent (`secondaryTitle` / `secondaryAccessibilityID` / `onSecondary`,
all `nil`-defaulted and iOS-gated) to add an optional "Select All" affordance:

- In `ChecklistSelectionView`, add optional fields (e.g. `selectAllTitle`, and
  an `onSelectAll` callback) that draw a button which sets
  `selection = rows.map { $0.id }` (all rows selected). Keep the import caller
  unchanged by leaving the new fields unset there. The confirm/action-button
  chrome (`actionButton`, `CardPlate.*`) and the existing `canConfirm`
  disable logic are the patterns to reuse.
- In `ExportChecklistsView`, pass the new fields so the export sheet shows the
  "Select All" button.
- Add a new user-facing string (e.g. "Select All") to `Localizable.xcstrings`
  across all 6 languages, plus a `LocalizationFixtures.requiredKeys` entry (see
  the `localization` skill). Run `scripts/l10n-check.sh` first.
- Add/extend tests in `CheckStitchTests/ExportChecklistsViewTests.swift`
  (expose a pure helper like `toggled`/`canConfirm` for the select-all logic if
  the sheet needs one) so both the happy path (button selects every row) and
  the export-only scoping (import sheet is unaffected) are covered.

Verify with `make test-unit` (fast), then the full `bash scripts/test.sh` gate
before committing. Window-less — no simulator boot is required for this UI
logic beyond what the gate already does.

## Why SMALL

Localized UI-only change (≤~5 files: the two views, localization, tests)
following the existing optional-param/action-button precedent; no schema, no
new subsystem, no design sign-off, and the test surface is small and local.

## Key files

- `CheckStitch/ChecklistSelectionView.swift` — shared multi-select sheet; add
  the optional "Select All" affordance (pattern: `secondaryTitle`/`onSecondary`).
- `CheckStitch/ExportChecklistsView.swift` — wire the new fields in (35-line wrapper).
- `CheckStitch/ContentView.swift` — the import caller (leave unchanged / verify).
- `CheckStitch/Localizable.xcstrings` + `CheckStitchTests/LocalizationFixtures.swift`.
- `CheckStitchTests/ExportChecklistsViewTests.swift` — extend for select-all.