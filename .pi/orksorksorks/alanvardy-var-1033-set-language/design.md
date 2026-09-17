# Design Discussion — VAR-1033: set the app's UI language

## Current State

Three `Localizable.xcstrings` catalogs, one per compiled target, each with six
languages (`en, de, es, fr, ja, zh-Hans`) — `CheckStitchTests/LocalizationTestHelpers.swift:53-58`.
App catalog → `Bundle.main`; Core catalog → `Bundle.module`; watch catalog → its own `.main`.

Resolution is always the process/preferred localization: no `locale:` argument, no
overridden locale, no preference key anywhere. Two pipelines coexist and both must be
satisfied:

- `String(localized:table:bundle:)` — explicit `bundle: .main` at
  `CheckStitch/AppearanceMode.swift:71-73` and `CheckStitch/BackgroundSettingsView.swift:68-69`;
  `bundle: .module` at `CheckStitchCore/.../SharedStrings.swift:8-16`; defaulted elsewhere
  (`CheckStitch/DueDateLabel.swift:17-25`). Resolves by **bundle**; ignores SwiftUI's `\.locale`.
- SwiftUI `Text("literal")` / `LocalizedStringKey`. Resolves by the **`\.locale` environment**;
  ignores the bundle.

`AppearanceMode` is the canonical persisted-preference template: a Core `Sendable` enum
(`CheckStitchCore/.../AppearanceMode.swift`), an app `AppearanceModePreference` over
`UserDefaults.standard` key `"appearanceMode"` with raw-string validation and `.system`
fallback (`CheckStitch/AppearanceMode.swift:62-95`), an `@AppStorage` prop of the same key on
`ContentView` (`CheckStitch/ContentView.swift:11-15`), applied app-wide through per-OS delegates
(`CheckStitch/AppDelegate.swift:13-27,41-51,111-126`) plus a startup replay.

Settings is a modal sheet from `ContentView` (`:119-124`) wrapping `SettingsView`'s
`NavigationStack` + `Form` (`CheckStitch/SettingsView.swift:7-87`): first `Section` = Appearance
picker, then Background / Import and Export / About. The Appearance picker is **not** staged in
`SettingsBindings`; it writes straight through its `@Binding` to `@AppStorage`.

The watch is a separate `@main` process (`CheckStitchWatch/CheckStitchWatchApp.swift:4-14`) with
**no** settings UI, `@AppStorage`, delegates or entitlements file (the only entitlements in the
repo are `CheckStitch/AppGroup.entitlements`, KVS-enabled). Phone→watch state travels as one
WatchConnectivity application-context push (`CheckStitchCore/.../ChecklistSyncCoordinator.swift:35-38`,
`CheckStitchWatch/WatchSyncAdapter.swift`), decoded by `ChecklistSyncMessage.init?(userInfo:)`.

Catalog discipline is enforced: every key non-empty in six languages plus a canary that
non-English values differ (`CheckStitchTests/LocalizationTests.swift:50-87`). The hosted runner
resolves `String(localized:)` with the process locale, so the existing pin `String.en`
(`LocalizationTestHelpers.swift:8-16`) **cannot** observe a non-English result; the embedding tests
bypass `String(localized:)` and diff the compiled `.lproj` tables directly (`LocalizationTests.swift:69-76,101-123`).

## Desired End State

Settings shows an **Interface** section with the Appearance picker and a new **Language** picker
(`System, English, Deutsch, Español, Français, 日本語, 简体中文`). Picking a language immediately
re-renders the app UI — `ContentView`, the Settings sheet and subscreens, Core-sourced labels
(`AppearanceMode.title`) — with no restart. The choice persists across launches; `System` restores
the process language. The paired watch renders its catalog strings in the same language after the
phone's next context push, falling back to its last-known/system language on a cold launch.

Verification: `make test-unit` proves the override seam resolves a real non-English value and the
preference round-trips/falls back; `bash scripts/test.sh` is green; on the simulator a human sees
German after switching and German again after relaunch.

## Patterns to Follow

- **`AppearanceMode` end to end** — Core `Sendable` enum + app `*Preference` struct with
  `defaultsKey`, raw-string validation, fallback (`CheckStitch/AppearanceMode.swift:62-95`);
  `@AppStorage` of the same key (`ContentView.swift:11-15`); `onChange` → delegate apply
  (`ContentView.swift:105-110`); startup replay (`AppDelegate.swift:23-27`). Mirror it, do not
  invent a store.
- **`makeIsolatedDefaults()`** for every persistence test (`CheckStitchTests/TestFixtures.swift:10-12`,
  as in `AppearanceModePreferenceTests.swift:7-20`).
- **`SettingsView` picker shape** — `Picker(selection:)` + `ForEach(allCases)` + `Label` +
  `accessibilityIdentifier` (`SettingsView.swift:18-30`), with a render test
  (`ViewRenderTests.swift:35-44`).
- **Core seams stay faked/testable**: the language rides the existing `ChecklistSync` seam, not a new channel.
- **Catalog work is a first-class step**: new keys ("Interface", "Language") land in
  `CheckStitch/Localizable.xcstrings` with six real translations, or the canary suite fails.
- **Do NOT follow / do NOT touch**: the POSIX `DateFormatter` in `ChecklistExport.swift:23`
  (deliberate; must not follow the UI language); `InfoPlist.strings`; the App Group;
  `SharedStrings`' contract ("never a caller's bundle", `SharedStrings.swift:5-6`).
- **Do NOT follow**: `project.pbxproj` edits (`PBXFileSystemSynchronizedRootGroup`), and bare
  `name=` destinations in scripts.

## Design Decisions

1. **Runtime mechanism — spike-gated `Bundle` instance override + SwiftUI locale environment.**
   A `LanguageBundle: Bundle` subclass in Core overrides `localizedString(forKey:value:table:)`,
   forwarding to the selected `xx.lproj` sub-bundle and reading the code from one shared,
   lock-guarded `LanguageOverride` store. Core installs it on **both** needed bundles: `Bundle.module`
   (internal — only Core can reach it) and a caller-supplied `Bundle.main`. The SwiftUI root
   separately gets `.environment(\.locale, language.locale)`, because `Text` literals never consult
   a bundle. Apple does not support on-the-fly switching and `object_setClass` is an `isa` swap, so
   a **timeboxed spike runs before any UI work** and must prove: (a) `String(localized:...)` from
   `.main` *and* `.module` returns German under the swap on iOS 18.7 simulator + macOS; (b)
   `Text("key")` follows `\.locale` through a switch + re-render; (c) `System` leaves the English
   path byte-identical. If (a) or (b) fails, stop and fall back to restart-based `AppleLanguages`
   + a "Restart to apply" alert (Open Risk 1) — do not build the picker on an unverified mechanism.

2. **Targets: iOS app, macOS leg, and the paired watch.** iOS and macOS are one `MyApp` process
   with per-OS delegates (`MyApp.swift:10-33`), so one preference and one apply path covers both.
   The watch receives the language over the **existing WatchConnectivity application-context push**
   (Decision 6), applies it with the same Core override against its own `Bundle.main` plus
   `.environment(\.locale,...)`, and never gains a settings surface. No app-group/KVS entitlement
   work: app groups do not cross devices and the watch has no entitlements file today.

3. **Apply timing: immediate, no restart, replayed at startup.** Apply in `MyApp.init()` (before
   first render) and in `onChange(of: appLanguage)` on `ContentView`, mirroring `applyAppearance`'s
   replay (`AppDelegate.swift:23-27`); the macOS delegate applies on
   `applicationDidFinishLaunching`/`applicationDidBecomeActive` (`AppDelegate.swift:111-126`). A root
   `.id(appLanguage)` is **conditional**: it refreshes cached strings but tears down the presented
   Settings sheet mid-interaction, so add it only if the spike shows stale text — otherwise rely on
   the environment change plus the sheet's own re-render (the picker's `@AppStorage` drives
   `SettingsView` too).

4. **Settings placement: an "Interface" section.** Convert the existing first `Section`
   (`SettingsView.swift:18-30`) into `Section("Interface")` holding the Appearance picker (keep id
   `"appearancePicker"`) plus a new `Picker("Language", selection: $appLanguage)` with id
   `"languagePicker"`, `System` first. Options are **endonyms written as literals** (`English`,
   `Deutsch`, `Español`, `Français`, `日本語`, `简体中文`) — a language is named in its own language,
   so they are deliberately not catalog keys. At most one optional footer key; everything else is
   the two or three new App-catalog keys, each needing all six translations.

5. **Persistence: `AppLanguage` in Core + `AppLanguagePreference` on `UserDefaults.standard` key
   `"appLanguage"`, default `.system`.** Core enum is `Sendable`, raw values
   `system, en, de, es, fr, ja, zh-Hans`, exposing `code: String?` (nil for `.system`), `locale`,
   `endonym`, and a validating resolver. App-side `AppLanguagePreference` mirrors
   `AppearanceModePreference` (`CheckStitch/AppearanceMode.swift:81-90`): `object(forKey:) as? String`,
   validate, fall back to `.system`; surfaced as `@AppStorage("appLanguage") var appLanguage = AppLanguage.system`
   on `ContentView`. `.system` means "no override installed", so existing users see identical
   behaviour and no migration is needed. The watch stores the last pushed code under the **same key
   in watch-local `UserDefaults.standard`**, validated by the same Core enum, so a cold unsynced
   launch is still correct.

6. **Watch transport: a sibling `language` key in the existing application context.**
   `ChecklistSyncCoordinator.pushContext()` (`ChecklistSyncCoordinator.swift:35-38`) adds the code to
   the same dictionary; `ChecklistSyncKey` gains `language` and `ChecklistSyncMessage.context` becomes
   `.context(Data, language: String?)` so the watch receives it. Decode stays tolerant: a
   missing/unknown key yields `nil`, so an older phone or watch keeps working. No new request
   direction is needed — the watch's cold-launch `.requestChecklists` already triggers a re-push, and
   `receivedApplicationContext` is populated at activation (`WatchSyncAdapter.swift`).

7. **Verification strategy — test the seam directly, because the pin cannot.** New unit tests:
   (a) with the code set to `de`, `bundle.localizedString(forKey: "Appearance", ...)` equals the
   compiled `de.lproj` value — the real non-English assertion `LocalizationTests.swift:69-76` says
   the pin cannot make; (b) an unsupported code falls back to system; (c) `AppLanguage` resolution
   plus `AppLanguagePreference` round-trip and unknown-value fallback on `makeIsolatedDefaults()`;
   (d) `SettingsView` lists all languages, an analogue of `settingsViewListsAllAppearanceModes`;
   (e) sync round-trip of `.context` with and without a language, and `WatchChecklistStore` storing a
   pushed language while keeping the previous one for a malformed/absent push. Manual, stated
   explicitly: switch to Deutsch → Settings *and* `ContentView` labels render German immediately;
   relaunch → still German; pick System → back to the process language; watch refreshed from the
   phone shows its catalog strings in German. Gate: `bash scripts/test.sh` (fast loop
   `make test-unit`).

8. **Layering: the override lives in Core, the preference UI in the app.** `LanguageOverride` +
   `LanguageBundle` + the validation enum are Core so all three targets share one implementation;
   the app owns `AppLanguagePreference`, the picker and the delegate-style apply; the watch only
   consumes.

## What We're NOT Doing

- **No RTL / `layoutDirection` work** — all six locales are left-to-right.
- **No OS-level localization** — `InfoPlist.strings` (display name, Reminders permission prompts)
  and the app name in Settings stay in the system language; a runtime override cannot reach them.
- **No localization of user data** — checklist/item names, reminder content and the export filename
  (`ChecklistExport.swift:23`) are untouched.
- **No watch-side picker**, no App Group extension to the watch, no KVS preference, no new
  entitlement or build-setting work.
- **No new languages, no catalog re-translation** beyond the 2-3 new UI keys.
- **No Apple system per-app language registration**, and no sync with it.
- **No sync protocol version bump** — the language is an extra optional key.
- No child tickets; all work lands on VAR-1033.

## Open Risks

1. **The `isa` swap may not intercept `String(localized:)` on a given OS**, and Apple's DTS
   position is that no supported on-the-fly switch exists. Hence the spike gate; the documented
   fallback is restart-based (`AppleLanguages` + relaunch prompt), which changes the UX and forces
   a design revision.
2. **`Bundle.module` is internal to Core**, so the app cannot swap Core's bundle instance; Core must
   install the subclass itself. Any future Core bundle re-resolution silently drops Core strings
   back to the process language.
3. **`.id(appLanguage)` at the root dismisses the Settings sheet**; only use it if the spike proves
   stale text.
4. **Sync-protocol change**: `.context(Data)` → `.context(Data, language:)` edits a Core enum and its
   transport seam; wire compatibility with an un-updated watch or phone must be test-covered.
5. **Watch language depends on a successful push**; a never-synced watch shows the system language —
   legitimate but potentially confusing.
6. **New catalog keys must be translated in all six languages** or the gate's localization suites fail.
7. **`Text` literal localization is version-dependent**; if `\.locale` does not localize a literal on
   the shipped OS, that literal stays English while `String(localized:)` strings switch — a
   mixed-language UI the spike must rule out.
