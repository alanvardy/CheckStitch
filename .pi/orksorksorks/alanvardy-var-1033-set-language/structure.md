# Structure Outline

## Approach

Retire the runtime-override risk with a timeboxed spike, then build the
`AppearanceMode` template end to end for language: a Core `AppLanguage` enum +
`LanguageBundle` override seam, an app `AppLanguagePreference`, a Settings
picker that applies immediately and persists, then fan the same override out to
the whole app surface and to the watch over the existing WatchConnectivity
context push.

## Phase 0: Spike gate — prove the override mechanism (throwaway, not merged)

No shippable value; this retires the ticket's core unknown before any UI is
built. Timeboxed; code lives in a scratch branch/`#if DEBUG` probe and is deleted.

- (a) `LanguageBundle` subclass installed on `Bundle.main` **and** `Bundle.module`
  returns the compiled `de.lproj` value for a real key on iOS 18.7 simulator +
  macOS.
- (b) `Text("literal")` follows `.environment(\.locale, de)` through a switch +
  re-render (literal localization is version-dependent).
- (c) `System` leaves the `en` path byte-identical to today.

**Contract**: a written go/no-go. GO → Phases 1-4 as below. NO-GO → stop and
re-run `design` for the restart-based fallback (design Open Risk 1); do **not**
build the picker on an unverified mechanism.

**Verify**: probe output on both platforms; manual `Text` render check.

---

## Phase 1: Walking skeleton — pick a language, Settings switches, persists

The user opens Settings, picks Deutsch, and Settings' own labels plus a
Core-sourced label (`AppearanceMode.title`) re-render German immediately with no
restart; relaunching keeps German. Green tests prove the seam resolves a real
non-English value and the preference round-trips/falls back.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/AppLanguage.swift` (new),
`CheckStitchCore/Sources/CheckStitchCore/LanguageBundle.swift` (new),
`CheckStitch/AppLanguagePreference.swift` (new), `CheckStitch/SettingsView.swift`,
`CheckStitch/ContentView.swift`, `CheckStitch/Localizable.xcstrings`,
`CheckStitchTests/{AppLanguageTests,AppLanguagePreferenceTests,LanguageBundleTests,ViewRenderTests}.swift`,
`CheckStitchTests/LocalizationFixtures.swift`.

**Key changes**:
- `enum AppLanguage: String, CaseIterable, Sendable { case system, en, de, es, fr, ja, zhHans }`
  — `var code: String?` (nil for `.system`), `var locale: Locale`, `var endonym: String`,
  `static func resolve(_ raw: String?) -> AppLanguage`
- `enum LanguageOverride` — `static func set(_ code: String?)`, `static var currentCode: String?`
  (lock-guarded single shared store)
- `final class LanguageBundle: Bundle` — overrides
  `localizedString(forKey:value:table:)`; `static func install(appBundle: Bundle)`
  (resolves `xx.lproj`); Core self-installs on `Bundle.module`
- `struct AppLanguagePreference { static let defaultsKey = "appLanguage";
  init(defaults:key:); var rawValue: String; func setRawValue_(_:) }` — mirrors
  `AppearanceModePreference`
- `SettingsView`: first `Section("Interface")` holding the existing Appearance
  picker (id `"appearancePicker"`) + `Picker("Language", selection: $appLanguage)`
  id `"languagePicker"`, `ForEach(AppLanguage.allCases)`, endonym literals (not catalog keys)
- `ContentView`: `@AppStorage("appLanguage") var appLanguage = AppLanguage.system`;
  `.environment(\.locale, appLanguage.locale)` on the root; `onChange` applies
  override and `MyApp.init()`/startup replay re-applies

**Contract**: `AppLanguage.code`/`.locale`/`.endonym`, `LanguageOverride.set(_:)`
and `AppLanguagePreference.defaultsKey` — Phase 2 and 3 consume only these.
New App-catalog keys `"Interface"`, `"Language"` land here with all six
translations.

**Tests**: `AppLanguageTests` (resolution + fallback), `AppLanguagePreferenceTests`
(round-trip / unknown-value fallback on `makeIsolatedDefaults()`),
`LanguageBundleTests` (code `de` → `bundle.localizedString(forKey:"Appearance",…)`
equals the compiled `de.lproj` value; unsupported code → system),
`settingsViewListsAllLanguages` analogue of `settingsViewListsAllAppearanceModes`.
**Verify**: `make test-unit` (fast) then `make build`; simulator manual: pick Deutsch →
Settings labels German; relaunch → still German; pick System → English.

---

## Phase 2: Whole-app immediate re-render (all screens + Core strings)

Every screen — `ContentView`, `SettingsView` and its subscreens — and every
Core-sourced label switches language on pick, not just Settings; `System`
restores the process language. This is the "no restart, no stale text" outcome.

**Files**: `CheckStitch/ContentView.swift`, `CheckStitch/AppDelegate.swift`,
`CheckStitch/MyApp.swift`, `CheckStitchCore/.../SharedStrings.swift` (consume-only),
`CheckStitchTests/ViewRenderTests.swift`.

**Key changes**:
- Apply path centralised: `AppDelegate.applyLanguage(_:)` / `MacAppDelegate.applyLanguage(_:)`
  invoked from `ContentView.onChange(of: appLanguage)` and replayed in
  `applicationDidBecomeActive` / `applicationDidFinishLaunching`, mirroring
  `applyAppearance`
- macOS leg uses the same Core seam against `Bundle.main`
- Conditional root `.id(appLanguage)` **only if** the spike showed stale text
  (it tears down the Settings sheet) — otherwise rely on environment + re-render

**Contract**: `applyLanguage(_:)` delegate seam; no changes to `AppLanguage` or
`LanguageOverride` from Phase 1.

**Tests**: extended `ViewRenderTests` (subscreen + Core label render in a
non-system language); `LanguageBundleTests` byte-identical `System` path.
**Verify**: `make test-unit`, `make build-mac`; manual: switch on macOS and iOS,
confirm ContentView + Background/About subscreens switch, System returns to English.

---

## Phase 3: Watch renders the phone's language

After the phone pushes its next context, the paired watch renders its catalog
strings in the same language; a cold unsynced launch uses the last pushed code,
falling back to the system language.

**Files**: `CheckStitchCore/.../ChecklistSyncCoordinator.swift`,
`CheckStitchCore/.../ChecklistSync.swift`, `CheckStitchWatch/WatchSyncAdapter.swift`,
`CheckStitchWatch/CheckStitchWatchApp.swift`, `CheckStitchTests/ChecklistSyncTests.swift`.

**Key changes**:
- `ChecklistSyncKey` gains `language`; `ChecklistSyncMessage.context(Data, language: String?)`
  — decode tolerant of missing/unknown key (old phone/watch interoperate)
- `ChecklistSyncCoordinator.pushContext()` adds the code to the same dictionary
- Watch: store last code under `"appLanguage"` in watch-local `UserDefaults.standard`,
  validated by `AppLanguage.resolve`; install `LanguageBundle` on watch `Bundle.main` +
  `.environment(\.locale)`; no settings surface added

**Contract**: `.context(Data, language: String?)` wire shape and the tolerant
decode — the phone/watch transport Phase 4 hardens.

**Tests**: sync round-trip with and without a language; `WatchChecklistStore`
keeps the previous language for a malformed/absent push.
**Verify**: `make test-unit`, `make watch-build`; `bash scripts/run-watch.sh` +
manual: phone in Deutsch → watch catalog strings German after push.

---

## Phase 4: Hardening — sad paths, fallback, no mixed-language UI

Residual robustness and polish only: unknown/unsupported codes, absent sync,
cold-launch fallback, and ruling out mixed-language rendering.

**Files**: `CheckStitchTests/LanguageBundleTests.swift`,
`CheckStitchTests/AppLanguagePreferenceTests.swift`,
`CheckStitchTests/ChecklistSyncTests.swift`, `CheckStitchTests/LocalizationTests.swift`
(catalog discipline), plus any fix surfaced by `make build-mac`/`make watch-build`.

**Key changes**: fixes only — no new surface; validation/fallback edges made
explicit; any `.id(appLanguage)` decision finalised.

**Tests**: sad paths — unsupported stored code → `.system`; malformed/absent
language in context → previous/system; System byte-identical baseline;
catalog canary for the new keys in all six languages.
**Verify**: `bash scripts/test.sh` prints `gate: ok`; manual relaunch + watch
cold-launch checks stated in design Decision 7.

---

## Testing Checkpoints

- After Phase 0: go/no-go recorded; if NO-GO, stop and re-run `design`.
- After Phase 1: `make test-unit` + `make build` green; picker switch + relaunch persist demonstrated.
- After Phase 2: `make test-unit` + `make build-mac` green; whole-app switch and System restore demonstrated.
- After Phase 3: `make test-unit` + `make watch-build` green; watch receives the language.
- After Phase 4: `bash scripts/test.sh` → `gate: ok`.