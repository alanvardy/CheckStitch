# Task

Localize three user-facing strings that are currently hardcoded English literals in
SwiftUI views, moving them into the app's existing Xcode string-catalog localization
(`Localizable.xcstrings` + the `*.lproj` translation resources), with translations
added for each supported locale.

The three strings:

1. **"List"** — `CheckStitch/ChecklistDetailView.swift:51` — `Picker("List", …)` (the
   edit-checklist screen)
2. **"Number Reminders"** — `CheckStitch/ChecklistDetailView.swift:71` — `Label("Number Reminders", systemImage: "textformat.123")` (the
   edit-checklist screen; the ticket calls it "Number Reminder")
3. **"Import and Export"** — `CheckStitch/SettingsView.swift:67` — `Text("Import and Export")` (the Settings menu; the ticket calls it
   "Import Export")

The app is already fully localized (en/de/es/fr/ja/zh-Hans). Follow the exact
mechanism the surrounding translatable strings use: mark these literals the same way
the sibling "Export"/"Import"/"Number…" strings are handled elsewhere in these views,
add the English source strings to `Localizable.xcstrings`, and supply translated
values in each locale's `<lang>.lproj` resource so every supported language shows a
translation instead of falling back to English.

## Why SMALL

Localized change: three literal strings in two SwiftUI views plus the existing
localization resources — a single module, ≤~5 files, following the pattern already
used by the sibling "Export"/"Import" strings (criterion A). Approach known, 0–2
unknowns, no schema/migration, no new subsystem, no design decision, tests few/local
(B–F).

## Key files

- `CheckStitch/ChecklistDetailView.swift` (lines 51, 71)
- `CheckStitch/SettingsView.swift` (line 67)
- `CheckStitch/Localizable.xcstrings` and `CheckStitch/{en,de,es,fr,ja,zh-Hans}.lproj`
  — the translation resources to which the new strings must be added