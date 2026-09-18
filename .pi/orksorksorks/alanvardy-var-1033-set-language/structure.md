# Structure Outline

## Approach

Port SingleThread's working seam: a Core `AppLanguage` enum + `AppLanguagePreference`
(persisted under `UserDefaults.standard["appLanguage"]`) behind a
`@MainActor @Observable AppLocaleState.current`, injected as
`.environment(\.locale, …)` at the app roots so every `Text` re-resolves live;
convert the eager `String(localized:)` sites to `LocalizedStringResource` +
`resolved(in:)`, and push the choice to the watch over the existing
`ChecklistSyncMessage` seam. No Bundle subclassing, no `AppleLanguages`, no
relaunch.

Slices are ordered dependency → risk → value: Slice 1 front-loads the riskiest,
spike-unobservable integration (live `\.locale` re-render), Slice 2 makes the
flip total, Slice 3 is the watch, Slice 4 is hardening. There is no schema
migration, so no horizontal phase is needed; each new UI string lands in its
catalog (all six languages) as part of the slice that introduces it.

---

## Phase 1: Walking skeleton — pick a language in Settings and watch the UI flip, live

The user opens Settings → **Interface** → **Language**, picks *Deutsch*, and the
SwiftUI text already on screen (nav title "Settings", section headers, "Done")
re-renders in German with no relaunch; the choice survives a cold launch.

**Files** (Core + app root + Settings UI + catalog + tests):
- `CheckStitchCore/Sources/CheckStitchCore/AppLanguage.swift` (new)
- `CheckStitchCore/Sources/CheckStitchCore/AppLanguagePreference.swift` (new)
- `CheckStitchCore/Sources/CheckStitchCore/AppLocaleState.swift` (new)
- `CheckStitch/AppLanguage+Presentation.swift` (new)
- `CheckStitch/SettingsView.swift`, `CheckStitch/ContentView.swift`, `CheckStitch/MyApp.swift`
- `CheckStitch/Localizable.xcstrings`, `CheckStitchTests/LocalizationFixtures.swift`

**Key changes**:
- `public enum AppLanguage: String, CaseIterable, Sendable { case system, english = "en", german = "de", spanish = "es", french = "fr", japanese = "ja", simplifiedChinese = "zh-Hans" }`
- `AppLanguage.locale: Locale` — `.system → .current`, else `Locale(identifier: rawValue)`
- `static AppLanguage.load(from defaults: UserDefaults = .standard) -> AppLanguage` — unknown/absent → `.system`
- `struct AppLanguagePreference { init(defaults: UserDefaults = .standard, key: String = "appLanguage"); var rawValue: String; func setRawValue(_ raw: String) }` — mirrors `AppearanceModePreference`
- `@MainActor @Observable final class AppLocaleState { init(language: AppLanguage? = nil, defaults: UserDefaults = .standard); static let current; private(set) var language: AppLanguage; var effectiveLocale: Locale; func set(_ language: AppLanguage); nonisolated static var storedEffectiveLocale: Locale }`
- `extension AppLanguage { var title: LocalizedStringResource }` (app target) — `.system` → main-catalog `"System"` key, the six endonyms verbatim (not catalog keys)
- `SettingsView`: new first `Section("Interface")` with `Picker(selection: $appLanguage)` over `ForEach(AppLanguage.allCases)` + `Text(language.title).tag(language)`, `.accessibilityIdentifier("languagePicker")`; new `@Binding var appLanguage: AppLanguage`
- `ContentView`: build the write-through binding (`AppLocaleState.current.language` / `.set(_:)`) and pass it into `SettingsView`
- `MyApp`: add `.environment(\.locale, AppLocaleState.current.effectiveLocale)` to both the iOS and macOS `WindowGroup` roots (read inside `body` so `@Observable` drives re-render)

**Contract** (what later slices may depend on): `AppLanguage`, `AppLanguage.locale`,
`AppLocaleState.current` / `.effectiveLocale` / `.set(_:)` / `.storedEffectiveLocale`,
`AppLanguagePreference` + its `"appLanguage"` key, and the `\.locale` injection at
the roots. Later slices must not read `AppLanguagePreference` directly — only the holder.

**Tests**: new `AppLanguageTests.swift` (`everyCaseMapsToItsCatalogLocale`, system→current),
new `AppLanguagePreferenceTests.swift` (`roundTripPersists`, `unknownStoredValueFallsBackToSystem`,
using `makeIsolatedDefaults()`); updated `ViewRenderTests` (SettingsView now needs
`.constant(.system)` for `appLanguage`); `LocalizationTests` green with the new
`Interface`/`Language` keys added to the App catalog and `LocalizationFixtures.requiredKeys`.

**Verify**: `make test-unit` green; then `make build` and on this worktree's simulator
(`make run`) select Deutsch — "Settings"/"Interface"/"Done" change immediately, relaunch
keeps German. This is the only evidence for the live flip (the hosted runner cannot observe it).

---

## Phase 2: The whole app follows the choice — no mixed-language UI

After picking a language, **every** app string is in that language: the appearance
picker titles, background footer, due-date labels, checklist detail text and core
package strings, with no relaunch.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift`,
`.../AppearanceMode.swift`, `.../AppInfo.swift`, new `.../LocalizedString+Shared.swift`
(Core); `CheckStitch/AppearanceMode.swift`, `CheckStitch/BackgroundSettingsView.swift`,
`CheckStitch/DueDateLabel.swift`, `CheckStitch/ChecklistDetailView.swift`.
Every affected key already exists in the catalogs — this slice changes the
*mechanism*, not the translations.

**Key changes**:
- `SharedStrings.system|light|dark` etc.: `String` → `LocalizedStringResource` (`.module` bundle)
- `extension LocalizedStringResource { func resolved(in locale: Locale) -> String; func resolvedInAppLanguage() -> String }` — sets `resource.locale` **before** `String(localized:)` (the spike-proven seam)
- `AppearanceMode.title` (app + core) → `LocalizedStringResource`; call sites in the Settings picker, `BackgroundSettingsView` footer, `DueDateLabel`, `ChecklistDetailView` use `Text(resource)` (views) or `resolved(in:)` (non-View)
- Any app-generated string reaching EventKit at creation time resolves via `resolved(in: AppLocaleState.current.effectiveLocale)`

**Contract**: `LocalizedStringResource.resolved(in:)` / `.resolvedInAppLanguage()`,
and `SharedStrings` / `AppearanceMode.title` exposed as resources. No caller may
hold an already-resolved `String` across a render.

**Tests**: new `LocalizedStringResolutionTests.swift` pinning
`SharedStrings.dark.resolved(in: Locale(identifier: "de"))` and one app-catalog key
against the compiled catalog (if the hosted runner cannot observe it, assert via the
existing compiled-`.lproj` diff technique and record why); updated
`AppearanceModeTests` (`titlesResolveThroughTheCoreCatalog` for the resource shape).
Sad path: unknown key still falls back to its own text.

**Verify**: `make test-unit` green; `LocalizationTests` unchanged-and-green (keys are
untouched); manual simulator pass — switch language and confirm appearance titles,
background footer and due-date labels all change live with no English residue.

---

## Phase 3: The watch renders in the phone's language

The paired watch displays its UI in the language chosen on the phone, while running
and after a cold launch; it offers no picker of its own.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift` (message +
`WatchChecklistStore`), `CheckStitch/ChecklistSyncCoordinator` (push site),
`CheckStitch/WatchSyncAdapter.swift` if the branch needs it,
`CheckStitchWatch/CheckStitchWatchApp.swift` (root locale + cold-launch apply).

**Key changes**:
- `ChecklistSyncKey.language = "language"`
- `ChecklistSyncMessage.language(String)` — new case in `userInfo` and `init?(userInfo:)`; a malformed/unknown language string decodes to a rejected message, never a crash
- `WatchChecklistStore.receive`: `.language(let raw)` → `AppLanguage(rawValue:) ?? .system`, applied to the watch's `AppLocaleState` (persisted locally, so a cold launch keeps it)
- Phone: push `.language(AppLocaleState.current.language.rawValue)` alongside `pushContext()` and on activation / on receipt of `.requestChecklists`
- Watch root: `.environment(\.locale, AppLocaleState.current.effectiveLocale)`; `WatchChecklistStore` tests inject an isolated holder/defaults

**Contract**: `ChecklistSyncMessage.language(String)` + `ChecklistSyncKey.language`,
and the rule "the phone is the source of truth; the watch persists what it receives
and re-requests on activation". Unknown raw values degrade to `.system`.

**Tests**: new `AppLanguageSyncTests.swift` — round-trip `userInfo` ↔ `init?(userInfo:)`
for `.language("de")`; garbage value (`"xx"`) yields no change (sad path);
`WatchChecklistStore` applies + persists a received language;
`.language` does not disturb `checklists`.

**Verify**: `make test-unit` green; `make watch-build` compiles; manual
`bash scripts/run-watch.sh` — select Japanese on the phone, watch UI flips (or on next
activation if it was unreachable), then relaunch the watch app and confirm it stays Japanese.

---

## Phase 4: Hardening — close the leaks and make the flip observable

No user-visible residue remains: accessibility labels, `AppInfo`, reminder-creation
text and all remaining `String(localized:)` sites follow the chosen language; the
live flip is captured as reproducible simulator evidence.

**Files**: whatever the `String(localized:` grep inventory still flags (app + core +
watch), `CheckStitch/ChecklistCreator`/EventKit seam if it produces app text,
`scripts/tests/` or a documented manual procedure for the screenshot diff, and
`.pi/orksorksorks/alanvardy-var-1033-set-language/` notes recording what the user should see.

**Key changes**:
- Convert the residual eager sites (accessibility labels, `AppInfo`, creation-time text)
- Watch strings: confirm its five catalog keys + literals follow the watch's `\.locale`
- Robustness: language arriving before `start()`, repeated/duplicate `.language` messages, unknown raw value from an older phone build
- Documented verification: screenshot-diff procedure per the `simulator` skill, plus the explicit statement that the hosted gate cannot observe a language switch

**Contract**: none new — this slice only removes the remaining direct
`String(localized:)` call sites and records the verification recipe.

**Tests**: sad-path suites for the malformed/duplicate-sync and unknown-preference
cases; full gate sweep.

**Verify**: `bash scripts/test.sh` prints `gate: ok`, and the recorded simulator
screenshot diff shows the same screen in German after selecting Deutsch vs. English
before the switch.

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` green + simulator shows a live flip of Settings'
  SwiftUI literals and a persisted choice. Do not proceed until the live flip is seen
  (this is the whole design's risk).
- **After Phase 2**: `make test-unit` + `LocalizationTests` green, and one manual pass
  shows no English residue anywhere on the Settings and checklist screens after a switch.
- **After Phase 3**: `make test-unit` + `make watch-build` green; watch shows the phone's
  language after a cold launch.
- **After Phase 4**: `bash scripts/test.sh` prints `gate: ok`; screenshot evidence recorded.
