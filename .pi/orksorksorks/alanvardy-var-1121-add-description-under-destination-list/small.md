# Task

Add a short description under the "Destination list" section header in the
Edit checklist screen, explaining where newly created reminders will land.

The section lives in `CheckStitch/ChecklistDetailView.swift`:

```swift
Section("Destination list") {
    Picker("List", selection: destinationBinding(checklistID: checklistID)) { ... }
    ...
}
```

Add a description `Text` right under the section, reading (primary copy):

> The reminders list where the newly created reminders will be placed

As the ticket also asks, suggest 1–2 alternative phrasings (e.g. "The Reminders
list the new reminders will be added to." or "Where the new reminders will be
created.") and pick the strongest one, being mindful of the ~6-language
localization (keep choppy sentences, no gendered/idiomatic phrases). Show the
chosen copy in the completion artifact.

## Why SMALL

Single module (`ChecklistDetailView.swift` + the `Localizable.xcstrings` string
catalog + its test fixture); a pure UI text addition with an already-known
approach and an existing pattern to follow (the surrounding `Text`/`Section`
layout). No schema, no migration, no new subsystem/integration, no
shared/convention code beyond the standard localization plumbing, no design
decision (the copy is provided; alternatives are optional polish).

## Key files

- `CheckStitch/ChecklistDetailView.swift` — add a `Text(...)` description under
  `Section("Destination list")` (around line 53).
- `Localizable.xcstrings` — add the new user-facing key in **all 6 languages**;
  run `scripts/l10n-check.sh` first.
- `CheckStitchTests/LocalizationFixtures.swift` — add the new key to
  `requiredKeys` (see the `localization` skill).
- Verify with `make test-unit`, then the full gate `bash scripts/test.sh`.