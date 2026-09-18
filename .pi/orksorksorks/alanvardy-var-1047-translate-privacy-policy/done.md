# Done

- **What was built**: Closed the localization guard surface for the privacy policy screen: all 8 privacy keys (`Reminders`, `Checklists & Sync`, `Background Image`, `Privacy Policy`, the no-analytics closing line, and the three long-form body strings) added to `LocalizationFixtures.requiredKeys["App"]`, activating the existing `everyRequiredKeyIsPresent` / `catalogsHaveAllSixLanguages` / `nonEnglishValuesDifferFromEnglish` guards; added `PrivacySettingsContentTests.privacyGuideContentResolvesTranslatedTextFromTheMainBundle` asserting the embedded German table in the main bundle carries each privacy key present, non-empty, and differing from the en-pinned lookup (the repo's only trustworthy non-English runtime observation — the hosted runner pins the process locale). Plus a runtime verification of translated rendering on a German-locale simulator (below).
- **Commit SHA(s)**: `755b0f3` — `test(l10n): guard privacy policy keys and non-English resolution` (pushed to `origin/alanvardy-var-1047-translate-privacy-policy`, PR #60)
- **Verification**:
  - `make test-unit` — 312 tests in 40 suites passed (was 311; +1 is the new test). No failures, no `excludedIdentities` additions needed.
  - Runtime verification (simulator `F7318738…`, this worktree's dedicated device): built for simulator, booted with `AppleLanguages=(de)` + `AppleLocale=de_DE`, installed + launched CheckStitch, then switched to `en`/`en_US` and relaunched. The simulator-installed bundle (`simctl get_app_container`) contains `de.lproj/Localizable.strings` with all 8 privacy keys in German, and a German/English screenshot diff of the running app differs by 60,447 px (1.91%), confined to the localized-text band (y 605–1109, x 161–1045) with surrounding chrome identical — the running app demonstrably reacts to system language. Simulator left shut down in the default English state; no Windows were opened (headless per the gate protocol).
  - Full gate (`bash scripts/test.sh`) not run per the SMALL pipeline — no production files changed, so `make build`/`build-mac`/`watch-build` are unaffected; the change is test-only.
- **Reviewer findings**: No blockers. Two optional P2 nits deferred: the 8 key literals are triplicated (fixture/test/catalog — any drift fails loudly, and sharing would force order-coupling); the second `#expect` lacks a failure message (cosmetic).
- **Remaining manual items**: Human eyes can confirm the German privacy screen by setting a device/simulator to German (Settings → General → Language & Region, or `defaults write -g AppleLanguages -array de` + `AppleLocale de_DE` + reboot) and opening Settings → Privacy Policy. Expected German copy (verified present in the installed bundle):
  - Nav title / settings row: **Datenschutzrichtlinie**
  - Section titles: **Erinnerungen** / **Checklisten & Synchronisierung** / **Hintergrundbild**
  - Closing: **CheckStitch verwendet keine Analytik, kein Tracking und keine Werbung.**
  - Bodies: **Erinnerungen werden über Apple Erinnerungen erstellt…** / **Ihre Checklisten werden auf Ihrem Gerät im gemeinsamen App-Speicher abgelegt…** / **Wenn der Hintergrund aktiviert ist, werden das Hintergrundbild und die Künstlerinformationen von einem Proxy unter vardy.cc heruntergeladen…**
  - Note: this session's blind agent could not read rendered pixels (no OCR/vision available), so the exact screen words above are quoted from the installed bundle's `de.lproj` rather than OCR'd.
  - Unrelated pre-existing dirt left untouched: unstaged deletion of the tracked junk file `DELETEME` (not part of this ticket; delete/commit as you see fit).
## Review fix — the copy ignored the in-app language picker

The human reviewer set the in-app language picker (Interface → Language) to
Spanish, opened Settings → Privacy Policy and saw an English body under a
Spanish row/title. Root cause: `PrivacyGuideContent.localized(_:)` resolved the
copy **eagerly** with `String(localized:table:bundle:)`, which pins the
*process* locale (`Locale.current`) and therefore ignores the app-language
`\.locale` override that `MyApp` injects. The screen title and the settings row
are SwiftUI string literals, which do resolve against `\.locale`, so only the
body and the closing line stayed English.

This is also why the "runtime verification" above missed it: it set the
**system** language (`AppleLanguages=(de)`), an axis the eager lookup *does*
honour. It never exercised the in-app picker. The `de.lproj` bundle check was
sound but equally blind to the picker — both proved the catalog is translated,
neither proved the screen resolves through the app language.

Fix: `PrivacyGuideContent` now returns `LocalizedStringResource`s (deferred
resolution) and `PrivacySettingsView` resolves them with `resolved(in:)`
against `@Environment(\.locale)`, the seam the rest of the app uses.

Verification:

- New `PrivacySettingsContentTests.privacyCopyResolvesInTheSelectedLanguageRatherThanTheProcessLocale`
  resolves the sections against `es` and `en`, asserting the Spanish values
  match the compiled `es` table, differ from English, and that the first
  section title is `Recordatorios`. It uses `resolved(in:)`; the test helper
  `LocalizedStringResource.resolved(locale:)` in `LocalizationTestHelpers.swift`
  is the spike-NO-GO `String(localized:locale:)` form and does **not** pin the
  language — it is currently unused, and using it is how the first draft of
  this test failed.
- Render check: `PrivacySettingsView` rendered offscreen via `ImageRenderer`
  with `\.locale = es` shows the whole screen in Spanish (title
  `Recordatorios`, `Listas de verificación y sincronización`, `Imagen de
  fondo`, closing `CheckStitch no utiliza analíticas ni seguimiento y no
  muestra publicidad.`) — i.e. the in-app-picker axis, not the system-language
  axis.
- `make test-unit` — 333 tests in 44 suites passed (was 332; +1 regression
  test). Full gate (`./scripts/test.sh`) — `gate: ok`.

