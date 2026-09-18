# Task

Make the privacy policy section of the settings menu render its text in
whichever language the interface is set to (en, de, es, fr, ja, zh-Hans).

**Current state (recon findings):** the app already has a complete
localization system (`Localizable.xcstrings` catalogs for the App/Core/Watch
targets, all six languages, `String(localized:table:bundle:)` lookups, and a
test fixture `LocalizationFixtures.requiredKeys` guarding catalog keys).
VAR-1042 (already merged) added the privacy subscreen — and it shipped
wired through this system: `PrivacyGuideContent.localized()` resolves every
privacy string from the app catalog, all privacy keys exist in
`CheckStitch/Localizable.xcstrings` and are translated in all six languages,
and `make test-unit` passes (311 tests), including
`PrivacySettingsContentTests` and the localization guard suites.

So the remaining work is: (1) runtime-verify the privacy screen actually
renders translated in a non-English interface language (simulator launch with
a non-English locale; a static catalog check is not closing evidence for a
render ticket), (2) close the test-surface gap — the privacy keys are notably
**absent** from `LocalizationFixtures.requiredKeys["App"]`, so nothing guards
them from being dropped or reverted to English (extend the App requiredKeys
list with the five section/closing keys and the three long-form body strings,
and extend `PrivacySettingsContentTests` to assert non-English resolution,
mirroring the existing `String.en`/pinned-locale pattern), and (3) fix
anything the verification surfaces. If verification shows the strings do not
localize at runtime, the fix is confined to the lookup plumbing in
`PrivacySettingsContent.swift` and/or the catalog.

Scope: app target + its test suite only — the watch app has no settings or
privacy screen, and there is no schema/API/storage change.

## Why SMALL

A–F all hold: single module + its tests, ≤5 files, follows the repo's
existing xcstrings/localized() pattern that this very feature already uses;
0–2 unknowns (the runtime-resolution question, with a known verification
path); no schema/migration; no new subsystem or shared/convention risk (catalog
edits and fixture additions are the established norm here); no design
decision/sign-off; tests needed are few, local, and follow existing
localization-test fixtures.

## Key files

- `CheckStitch/PrivacySettingsContent.swift` — `PrivacyGuideContent` +
  `localized()` plumbing (already wired; the only code-side fix candidate)
- `CheckStitch/PrivacySettingsView.swift` — renders the sections (nav title
  "Privacy Policy")
- `CheckStitch/SettingsView.swift` — the "Privacy Policy" settings row label
- `CheckStitch/Localizable.xcstrings` — app catalog; privacy keys present and
  translated in en/de/es/fr/ja/zh-Hans
- `CheckStitchTests/LocalizationFixtures.swift` — `requiredKeys["App"]` is
  missing every privacy key; extend the guard
- `CheckStitchTests/PrivacySettingsContentTests.swift` — extend to assert
  non-English resolution (pinned-locale `String.en` pattern)
- `CheckStitchTests/LocalizationTestHelpers.swift`, `LocalizationTests.swift` —
  existing catalog-parse/locale-pin helpers and guard suite to extend