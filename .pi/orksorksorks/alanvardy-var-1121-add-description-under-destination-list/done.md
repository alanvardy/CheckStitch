# Done

- **What was built**: A footnote description under the "Destination list"
  section header in the Edit checklist screen (`CheckStitch/ChecklistDetailView.swift`),
  explaining that the picker selects where newly created reminders land. The
  string is localized in all 6 languages and registered in the localization
  test fixture.

- **Copy chosen**: *"The Reminders list where the new reminders will be added."*
  - Alternatives suggested:
    1. "The reminders list where the newly created reminders will be placed"
       (ticket primary copy)
    2. "Where the new reminders will be created."
  - Rationale: option 1 (chosen) is the shortest sentence that names both the
    destination ("Reminders list") and the consequence ("new reminders ...
    added"); it keeps a single clause, avoids the wordy "newly created", and
    has no gendered/idiomatic constructions, so it translates cleanly across
    the 6 supported languages. The primary copy is accurate but repeats
    "reminders" three times in a longer phrase.

- **Commit SHA(s)**: `257e62782d79fceed3a6eeb05a3ba3434cc0df74`
  ("feat: add description under Destination list in Edit checklist screen") —
  already pushed to `origin/alanvardy-var-1121-add-description-under-destination-list`.

- **Verification**:
  - `bash scripts/l10n-check.sh` → `ok (4 catalogs, 177 keys, 6 languages)`
  - `make test-unit` → 603 tests in 67 suites passed (includes the
    `requiredKeys` / non-English-differs localization canaries)
  - `bash scripts/test.sh` (full gate) → `gate: ok` (26 shell tests passed)

- **Reviewer findings**: No blockers. One nit: the chosen copy capitalizes
  "The Reminders" (app name) where the ticket primary copy used sentence case —
  intentional and consistent with the file's header capitalization; no change
  made. Reviewer independently confirmed placement, byte-for-byte key ↔
  literal ↔ fixture consistency, and that all 6 language values are genuine
  translations (no leftover English).

- **Remaining manual items**: None. Screen is a localized UI-text addition;
  no device/sync verification required by the ticket. The change is already
  committed and pushed; open the PR / merge when ready.
