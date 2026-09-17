# Task

Add a privacy policy disclosure screen to CheckStitch's Settings, adapted from the SingleThread reference implementation (`SingleThread/PrivacySettingsContent.swift`, `SingleThread/PrivacySettingsView.swift`, and the link row in `SingleThread/SettingsView.swift`).

Mirror CheckStitch's existing About-subscreen pattern end to end:

- **New `CheckStitch/PrivacySettingsContent.swift`** — port `PrivacySettingsContent.swift`: static `PrivacySection`-typed disclosure sections + a closing line, plus the `localized()` helper resolving through the app's `Localizable` bundle. Adapt the copy to CheckStitch's actual data flows, which you must read from the code: checklists stored in shared app storage / KVS and synced through the user's own iCloud, reminders created via EventKit into the Reminders inbox (the app never reads/deletes/completes reminders after creation), and the background-image fetch in `BackgroundImageStore.swift` (the one network request — a proxy at `vardy.cc`, verify what it sends). Add any new strings to `CheckStitch/Localizable.xcstrings` (with the other locale `.lproj` catalogs as needed).
- **New `CheckStitch/PrivacySettingsView.swift`** — port `PrivacySettingsView.swift`: a read-only `Form` rendering the sections (`Section(section.title) { Text(section.body) }`, closing line in a footer), titled "Privacy Policy" (`.navigationTitle` per `AboutView` precedent) and `.settingsSubscreenLayout()`.
- **Edit `CheckStitch/SettingsView.swift`** — add a "Privacy Policy" `NavigationLink` row in its own `Section`, mirroring the existing About row, with `.accessibilityIdentifier("settingsPrivacyRow")`.
- **New `CheckStitchTests/PrivacySettingsContentTests.swift`** — port the SingleThread content tests (`PrivacySettingsContentTests.swift`): sections non-empty and the no-analytics/no-tracking/no-advertising claim, adapted to CheckStitch's copy.

Verify with `make test-unit` first, then the full gate `bash scripts/test.sh`.

## Why SMALL

A localized read-only UI addition (~4 files + the localization catalog) that copies existing patterns end to end — CheckStitch's About-subscreen precedent (`SettingsView` → `NavigationLink` → `AboutView` with `settingsSubscreenLayout()`) and SingleThread's own privacy implementation, which the ticket names as the reference. No schema/migration, no new subsystem or integration, no shared/convention code, no design decision — the only open question is which CheckStitch data flows the disclosure copy must describe, answerable directly from the code. Tests are one local content suite following `AboutViewTests`/`LocalizationTests` precedent.

## Key files

- `CheckStitch/SettingsView.swift` — add the Privacy Policy row (mirror the About `Section`)
- `CheckStitch/AboutView.swift` — subscreen precedent the new view mirrors
- `CheckStitch/Localizable.xcstrings` (+ locale `.lproj` catalogs) — new disclosure strings
- `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift` — bundle/module localization precedent
- `CheckStitch/BackgroundImageStore.swift` — facts for the background-image disclosure section
- `CheckStitchTests/AboutViewTests.swift` / `LocalizationTests.swift` — test precedents
- Reference: `/Users/vardy/dev/SingleThread/SingleThread/PrivacySettingsContent.swift`, `PrivacySettingsView.swift`, `SingleThread/SettingsView.swift`, `SingleThreadTests/PrivacySettingsContentTests.swift`