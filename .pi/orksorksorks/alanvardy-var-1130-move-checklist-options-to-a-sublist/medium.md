# Task

The edit-checklist screen has too many controls on one form. Create a new
subscreen called **"Checklist Options"**, reachable from a **"Checklist
Options"** button/link placed under the checklist name on the edit screen.

Move these five existing controls off the edit-checklist form and onto the
Checklist Options subscreen, unchanged in behaviour:

- **Destination list**
- **Number Reminders** (label should read "Number Reminders" — do not
  capitalize "reminders" here)
- **Scaling**
- **Factor**
- **Show on watch**

This is a pure UI relocation: the underlying values still live in
`ChecklistStore` (`setDestination`, `setPrefixesReminderNumbers`,
`setScaling`, `setShowsOnWatch`) and must keep working exactly as before.

## Why MEDIUM

Breadth triggers matched: **MULTI_MODULE** (≈6 files across the app target,
the string catalog, fixtures and two test suites) and **BROAD_TEST_SURFACE**
(the 28-test `ChecklistDetailViewTests` suite plus localization
fixture/catalog tests all assert these controls and will need updating).
M1 holds — approach is known (follow the existing `NavigationStack` /
`NavigationLink` + `SettingsSubscreenLayout` precedent) — and M2 holds: no
schema, no new subsystem/integration, no core/API change, no design
trade-off; the localization catalog update follows the documented
all-6-languages + `requiredKeys` fixture procedure.

## Key files (recon findings)

- `CheckStitch/ChecklistDetailView.swift` — the edit screen; all five controls
  and their bindings/accessibility ids live here (~lines 58–126, helpers
  ~217–380). Where the "Checklist Options" link is added and sections removed.
- `CheckStitch/ContentView.swift:46,:83` — `NavigationStack(path: [UUID])` +
  `.navigationDestination(for: UUID.self)`; the only registered route today.
  A new subscreen needs a `NavigationLink` push (or an additional route value).
- `CheckStitch/SettingsSubscreenLayout.swift` — reusable pushed-subscreen
  layout helper (macOS top-align), used by settings subscreens
  (`SettingsView.swift:24`, `PrivacySettingsView.swift:47`,
  `ArchivedChecklistsView.swift:99`) — precedent for the new screen.
- `CheckStitch/Localizable.xcstrings` — existing keys `Scaling`, `Factor`,
  `Number Reminders`, `Show on watch`, footer strings; **no
  "Checklist Options" key yet** (new key needs all 6 languages).
- `CheckStitchTests/LocalizationFixtures.swift` (`requiredKeys` ~12–177, an
  identity `ExclusionEntry` for `Factor` at ~226) and
  `CheckStitchTests/LocalizationTests.swift` — add the new key to fixtures.
- `CheckStitchTests/ChecklistDetailViewTests.swift` (28 `@Test` funcs,
  ~355+ lines) — asserts `destinationListPicker`, `checklistScalingField`,
  `checklistScalingModePicker`, `checklistShowsOnWatchToggle`,
  `checklistPrefixNumbersToggle`, `checklistNameField`; primary suite to
  update for the moved controls.
- `CheckStitchTests/ViewRenderTests.swift:16–17` — render smoke for
  `ChecklistDetailView`; verify it still renders with the options moved out.

Not touched: `CheckStitchCore` (read-only store usage), watch target, codec /
scaling tests, UI smoke (`CheckStitchUITests`) — no matching identifiers.
