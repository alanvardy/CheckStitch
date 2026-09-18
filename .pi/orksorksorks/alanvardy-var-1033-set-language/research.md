# Research Findings

Repo root: `/Users/vardy/dev/alanvardy-var-1033-set-language` (slice of
`/Users/vardy/dev/CheckStitch`).

## Q1: How does localized-string resolution work at runtime?

### Findings
- Three `Localizable.xcstrings` catalogs, one per compiled target, each `"sourceLanguage": "en"` with six languages (`en, de, es, fr, ja, zh-Hans` — `CheckStitchTests/LocalizationTestHelpers.swift:58`):
  - App: `CheckStitch/Localizable.xcstrings` → app target's `.main` bundle (iOS + macOS)
  - Core: `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings` → Swift package `.module` bundle
  - Watch: `CheckStitchWatch/Localizable.xcstrings` → watch app's own `.main` bundle
- Resolution entry point is Foundation `String(localized: LocalizationValue, table: "Localizable", bundle:)`. Bundle explicit at `CheckStitch/AppearanceMode.swift:71-73` and `CheckStitch/BackgroundSettingsView.swift:68-69` (`.main`); `CheckStitchCore/Sources/CheckStitchCore/SharedStrings.swift:8,12,16` (`.module`, "never a caller's bundle"); unguarded default at `CheckStitch/DueDateLabel.swift:17-25`, `CheckStitch/ChecklistDetailView.swift:296`.
- **No production call site selects the language.** No `locale:` argument anywhere in app code; Foundation resolves by process/preferred localization. Documented in-repo: the hosted test runner "resolves `String(localized:)` with the process locale" (`CheckStitchTests/LocalizationTests.swift:77-78`, `:104-105`).
- Fallback: an unknown key resolves to its own literal text (`CheckStitchTests/LocalizationTests.swift:126-128`).
- Catalogs are compiled into each target as `.lproj` resource tables; app code never opens a catalog at runtime. Tests reach the compiled tables via `Bundle.main.url(forResource: "Localizable", withExtension: "strings", localization: "de")` (`CheckStitchTests/LocalizationTests.swift:108-112`, core analog `:70-98`).
- Locale-related APIs in the tree (complete inventory):
  - `Locale(identifier: "en")` — test-only pin, `CheckStitchTests/LocalizationTestHelpers.swift:8-16`
  - `Locale(identifier: "en_US_POSIX")` — one `DateFormatter` for a deterministic export filename, not catalog text (`CheckStitchCore/Sources/CheckStitchCore/ChecklistExport.swift:23`)
  - `InfoPlist.strings` per `.lproj` per language: asserted, not executed at runtime (`CheckStitchTests/LocalizationTests.swift:130-146`) — feeds OS display name / permissions prompts, not in-app rendering
- Deliberately avoided (zero references repo-wide): no `LC_ALL`/`LANG`/`LC_CTYPE` env handling in `scripts/` or `Makefile`; no preferred-languages hook, `UIApplication`-level language API, per-language persistence, or `UserDefaults` language key. Only persisted-pref machinery is `AppearanceModePreference` + `AppGroup.defaults` (`CheckStitch/AppGroup.swift:6-11`) — appearance only.
- Empirical prior: "`String(localized:locale:)` does not pin language in the hosted test runner — the process locale wins", recorded at `.pi/orksorksorks/alanvardy-var-986-add-localizations/implement.md:31` (prior-ticket plan artifact).
- **Unknown territory confirmed**: nothing in the codebase sets or overrides the resolved locale; the mechanism to override at runtime is an open question (see Open Areas).

## Q2: What patterns exist for a user-persisted preference?

### Findings
- **Dual enums**: app `enum AppearanceMode: String, CaseIterable { system, light, dark }` (`CheckStitch/AppearanceMode.swift:5-7`), with per-mode platform mappings `windowOverrideStyle` (iOS `UIUserInterfaceStyle`, `.system`→`.unspecified`), `appKitAppearance` (macOS `NSAppearance?`, `.system`→`nil`), `colorScheme`, `systemImage`, `title` (`:13-60`); public `Sendable` twin in core (`CheckStitchCore/Sources/CheckStitchCore/AppearanceMode.swift`), whose `title` goes through `SharedStrings` (`:74-78`).
- **Read path**: `AppearanceModePreference` (`CheckStitch/AppearanceMode.swift:68-95`) — `init(defaults: UserDefaults = .standard, key: String = defaultsKey)`, `static let defaultsKey = "appearanceMode"` (`:77`), `rawValue` = `defaults.object(forKey: key) as? String` validated against `["system","light","dark"]` else `"system"` (`:81-86`), `setRawValue_` writes `defaults.set(raw, forKey: key)` (`:88-90`). `AppearanceMode.load(from defaults = .standard)` = `Self(rawValue: …) ?? .system` (`:62-65`), comment "mirrors `@AppStorage` fallback-to-default".
- **SwiftUI-tier persistence**: `@AppStorage` props on `ContentView`, property initializers are the defaults when the key is absent: `@AppStorage("appearanceMode") var appearanceMode = AppearanceMode.system`, plus `backgroundEnabled`, `backgroundFadePercent = BackgroundFade.defaultValue`, `backgroundPinned` (`CheckStitch/ContentView.swift:11-15`). Both the prefs struct and `@AppStorage` share the same key + same validation fallback.
- **Apply path**: `.onChange(of: appearanceMode)` → `AppDelegate.applyAppearance(new)` (iOS, `CheckStitch/ContentView.swift:105-110` → `CheckStitch/AppDelegate.swift:13-25` sets `window.overrideUserInterfaceStyle` on every connected scene; startup replay `applicationDidBecomeActive` → `applyAppearance(AppearanceMode.load())`, `:23-27`) / `MacAppDelegate.applyAppearance` (`:41-51`, `window.appearance = mode.appKitAppearance` on all `NSApp.windows`; loads at `:111-120,122-126`).
- **Settings write-through vs staged**: appearance Picker holds a direct `@Binding var appearanceMode: AppearanceMode` into `SettingsView` (`CheckStitch/SettingsView.swift:8-10,21-24`) — writes straight through `$appearanceMode` and the `@AppStorage` prop persists it. Background prefs are staged in a `SettingsBindings` snapshot bag (`CheckStitch/SettingsBindings.swift:1-25`) created by `makeSettingsBag()` (`ContentView.swift:586-590`), written back on change via `writeBack(bag)` (`ContentView.swift:545-552`) to the `@AppStorage` props ("survives relaunch").
- **Per-platform stores**: `UserDefaults.standard` default for prefs; `AppGroup.defaults` = `group.app.alanvardy.CheckStitch` app group (`CheckStitch/AppGroup.swift:1-12`), used by `ChecklistStore` (`CheckStitch/ChecklistStore.swift:34,50`); `NSUbiquitousKeyValueStore.default` key `"checklists.v1"` in `ChecklistSyncStore` (`CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift:20-45`) — checklist sync, not preferences.
- **Tests**: `CheckStitchTests/AppearanceModePreferenceTests.swift:7-20` (round-trip, unknown-value fallback), `CheckStitchTests/AppearanceModeTests.swift:7-26` (raw-value rewrites + `load`, `titlesResolveThroughTheCoreCatalog`), `CheckStitchTests/SettingsBindingsTests.swift:17-62` (staging never writes; snapshot reads current defaults; `writeBackPersistsEachKey` via `ContentView.writeBack`, cleanup `UserDefaults.standard.removeObject`). Shared helper `makeIsolatedDefaults()` defined in `TestFixtures.swift` (`CheckStitchTests/TestFixtures.swift:10-12`).

## Q3: How is the Settings screen structured?

### Findings
- **Entry**: gear button (`ContentView.swift:301-322` iOS / `324-333` macOS) sets `settingsBag = makeSettingsBag()` then `isShowingSettings = true`; sheet presented at `ContentView.swift:119-124` (`.sheet(isPresented: $isShowingSettings) { if let bag = settingsBag { settingsSheetWritebacks(bag) } }`); on dismiss clears the bag and replays staged `dataActionQueue` actions after 400 ms (`:125-141`).
- **SettingsView tree** (`CheckStitch/SettingsView.swift:7-87`): `NavigationStack` (line 14) wrapping a `Form` with four `Section`s + toolbar:
  1. **Appearance** (18-30): `Picker(selection: $appearanceMode)` over `ForEach(AppearanceMode.allCases, id: \.self) { Label(mode.title, systemImage: mode.systemImage).tag(mode) }`, `.accessibilityIdentifier("appearancePicker")`.
  2. **Background** (32-40): `NavigationLink { BackgroundSettingsView(...) }`, id `"settingsBackgroundRow"`.
  3. **Import and Export** (42-51): `Button(onExport)` / `Button(onImport)` rows, ids `"settingsExportRow"`/`"settingsImportRow"`.
  4. **About** (53-58): `NavigationLink { AboutView() }`, id `"settingsAboutRow"`.
- Toolbar: `.navigationTitle("Settings")`, `.toolbarTitleDisplayMode(.inline)` (71-72), `ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }` (73-82) via `@Environment(\.dismiss)` (12); macOS-only `.preferredColorScheme(appearanceMode.colorScheme)` (84-86) because `NSWindow.appearance` isn't seen by the Canvas.
- **Appearance Picker flow**: not staged (bag holds only the three background keys, `SettingsBindings.swift:4-6`); Picker writes through `$appearanceMode` → `@AppStorage("appearanceMode")` persists (`ContentView.swift:26-27`) → `.onChange(of: appearanceMode)` applies via delegate (`ContentView.swift:105-110`); `.preferredColorScheme` threading at `ContentView.swift:114-119` and `SettingsView.swift:84-86`; startup replay `AppDelegate.swift:23-27`.
- **Subscreens**: `BackgroundSettingsView.swift:3-79` (Toggle + fade Picker + pinned Toggle + refresh Button + footer credit via `String(localized:, table:, bundle: .main)` at `:68-69,72-77`; `.navigationTitle("Background")` + `.settingsSubscreenLayout()` `:78-79`); `AboutView.swift:4-44` (identity, copyright/version, footer `mailto:` Link; own `.navigationTitle("About")` + `.settingsSubscreenLayout()`).
- `SettingsSubscreenLayout.swift:3-31`: macOS-only `ViewModifier` top-align fix; iOS no-op.
- **Placement precedent**: the appearance Picker is a standalone first `Section` (18-26); sibling sections at the same level are Background (32-39), Import/Export (42-51), About (53-58). The "interface" grouping would sit among these within the shared `NavigationStack`/`Form`.
- Tests pinning this surface: `CheckStitchTests/ViewRenderTests.swift:35-44` (`settingsViewListsAllAppearanceModes`), `SettingsBindingsTests.swift` (writeback), render views use `.constant(.system)` bindings (`ViewRenderTests.swift:37,50,61`).

## Q4: How does each platform target start up and apply app-wide config?

### Findings
- **Two `@main` apps**: `CheckStitch/MyApp.swift:10` (`@main struct MyApp: App`) compiles both iOS and macOS — no separate entry file; `CheckStitchWatch/CheckStitchWatchApp.swift:4-14` (`@main struct CheckStitchWatchApp`) for the watch.
- Delegates: iOS `@UIApplicationDelegateAdaptor(AppDelegate.self)` (`MyApp.swift:12`), macOS `@NSApplicationDelegateAdaptor(MacAppDelegate.self)` (`MyApp.swift:16`).
- Shared startup (both targets): `init()` builds `ChecklistStore` + `ChecklistSyncService(sync: UbiquitousChecklistSync(), store:)`, starts it, publishes via `@State` (`MyApp.swift:26-33`).
- Per-target `body`: `WindowGroup { ContentView().environment(store).environment(syncService) }`; macOS `.restorationBehavior(.disabled)` + scenePhase flush/push (`:42-55`), iOS `ChecklistSyncCoordinator` + store-change hook + same flush (`:57-83`). Per-target ContentView forks: macOS toolbar (`ContentView.swift:68-86`), iOS `.containerBackground(.clear, for: .navigation)` (`:92-95`).
- **Where prefs load/apply**: `ContentView` `@AppStorage` seeds appearance (`ContentView.swift:11`); iOS delegate `applicationDidBecomeActive` → `applyAppearance(AppearanceMode.load())` (`AppDelegate.swift:23-27`); macOS `applicationDidFinishLaunching` (`:111-120`) + `applicationDidBecomeActive` (`:122-126`), with window frame clamping and `NSWindow.didMoveNotification`/`willCloseNotification` observers; `applicationShouldTerminateAfterLastWindowClosed → false`, `applicationShouldHandleReopen → true` (`:128-134`).
- **Watch: no settings machinery at all** — grep for `AppearanceMode|applyAppearance|applicationDid*` in `CheckStitchWatch/` returns nothing; no delegates, no `@AppStorage`. Watch store is `WatchChecklistStore(transport: WatchSyncAdapter())` (`CheckStitchWatchApp.swift:7-13`), store type in Core (`CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift:65`).
- **Bundle/table per target**: app strings resolve `bundle: .main` (explicit `CheckStitch/AppearanceMode.swift:71-73`, `BackgroundSettingsView.swift:69`; defaulted elsewhere, e.g. `ChecklistDetailView.swift:296`); watch uses its own catalog, also `.main` (explicit `CheckStitchWatch/WatchChecklistDetailView.swift:28-29`; most watch strings are plain literals — `WatchChecklistListView.swift:12,21-22`); core strings `.module` (`SharedStrings.swift:8-16`, `AppInfo.swift:38,43`).

## Q5: What do the localization test suites assert?

### Findings
- One test bundle target `CheckStitchTests` (`com.apple.product-type.bundle.unit-test`, `CheckStitch.xcodeproj/project.pbxproj:163-185`), hosted: `TEST_HOST`/`BUNDLE_LOADER` = the `CheckStitch` app (`pbxproj:578,598,614`), `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"` (`:587`), iOS 18.7 / macOS 27.0 deployment targets. Swift Testing `@Test` (not XCTest). No localization tests in `CheckStitchCore` package or `CheckStitchUITests` (UI smoke launches + accessibility audit only, `CheckStitchUITests/CheckStitchUITests.swift:1-40`).
- **Helpers** (`CheckStitchTests/LocalizationTestHelpers.swift`): `Catalogs.languages = ["en","de","es","fr","ja","zh-Hans"]` (53-58); `repoRoot` via `#filePath` (57-60); `Catalogs.all` names the three `.xcstrings` paths (61-68); `load`/`loadAll` parse xcstrings JSON; `Bundle.core` resolves the embedded `CheckStitchCore_CheckStitchCore.bundle` from `.main`, precondition-fails if absent (21-43); `String.en(_:bundle:table:)` pins `Locale(identifier: "en")` (8-16).
- **Assertions** (`CheckStitchTests/LocalizationTests.swift`):
  - `catalogsParseAndHaveNonEmptyEnglish` (21-36 — L9-18 per report), `catalogsHaveAllSixLanguages` (38-48)
  - `everyRequiredKeyIsPresent` (50-59) against `LocalizationFixtures.requiredKeys`; `watchCatalogCarriesEveryUIKey` (61-69)
  - canary `nonEnglishValuesDifferFromEnglish` (71-87) over `guardedCatalogs = ["App","Core","Watch"]` minus `excludedIdentities`
  - embedded-bundle diffs: `coreCatalogValuesAreEmbeddedInTheResourceBundle` reads the **compiled** `de.lproj/Localizable.strings` via `Bundle.core.url(...)` (89-127); `appCatalogIsEmbeddedInTheMainBundle` for `Bundle.main` (129-148)
  - `unknownKeyFallsBackToItsOwnText` (150-152); `infoPlistStringsHaveRequiredKeysPerLanguage` + sad path (154-183); `malformedCatalogThrows` (185-192); `missingResourceBundleResolvesToNil` (194-196)
- **Fixtures** (`CheckStitchTests/LocalizationFixtures.swift`): `guardedCatalogs` (8), `requiredKeys` App ~70 keys / Core 5 / Watch 5 (16-82), `infoPlistTargets` App requires `NSRemindersFullAccessUsageDescription`, `NSRemindersUsageDescription`, `CFBundleDisplayName`; Watch only `CFBundleDisplayName` (92-104), `excludedIdentities` (106-121).
- **Locale pinning limit**: `String.en(...)` makes assertions host-locale independent, but the hosted runner resolves `String(localized:)` with the process (English) locale, so a pin cannot observe e.g. German — the embedding tests bypass `String(localized:)` and diff the compiled `de.lproj` tables via `PropertyListSerialization` (`LocalizationTests.swift:69-76,101-123`). **Consequence**: any new dynamically-resolving locale mechanism cannot be asserted through the current pin; a language switch changes what `String(localized:)` returns only if it changes the process/preferred localization.

## Q6 (post-spike): Runtime override mechanism — empirically resolved (NO-GO for Bundle subclassing)

Spike evidence record: `.pi/orksorksorks/alanvardy-var-1033-set-language/spike.md`,
`spike-ios-report.txt` (raw iOS probe output), `phase0_output.md` (worker run
record). Probe code was throwaway and deleted.

### Findings
- The probe swapped `Bundle.main`'s `isa` (via `object_setClass`) to a
  `Bundle, @unchecked Sendable` subclass overriding the 3-arg
  `localizedString(forKey:value:table:)` and forwarding to the compiled
  `de.lproj` as a sub-bundle while an override code was installed. On the
  **iOS 18.7 simulator** (the plan's primary runtime) the redirect counter
  stayed `0` and `String(localized:)` returned English under the swap
  (`de-main={Settings}`, `de-core={Dark}`, `routing-3arg-redirects={0}`) — the
  runtime does not call the 3-arg method.
- `String(localized:)` on this toolchain routes through the 4-arg
  `localizedString(forKey:value:table:localizations:)`
  (`@available(macOS 15.4, iOS 18.4, …)`), declared in
  `extension Foundation::Bundle`; Swift 6 rejects an override:
  `instance method 'localizedString(forKey:value:table:localizations:)' is
  declared in extension of 'Bundle' and cannot be overridden` (macOS leg
  build error). A Bundle subclass cannot redirect `String(localized:)` on
  macOS 15 / iOS 18 — the runtime-override mechanism is a dead end.
- The explicit-locale **parameter** form
  `String(localized: key, table:, bundle:, locale: Locale(identifier: "de"))`
  also returned English (`explicit-de-main={Settings}`) — wrong seam too.
- The German data is present and decodable at runtime: opening the compiled
  `de.lproj` as its own `Bundle` and calling
  `localizedString(forKey: "Dark", value: "Dark", table: "Localizable")`
  returns `Dunkel` (`core-sub-bundle-lookup=Dunkel`).
- The nil/unsupported-code path with the subclass installed is byte-identical
  to baseline English (`restored-*-matches-baseline=true`) — a no-op override
  is safe but useless.
- Whether `Text("literal")` follows `\.locale` at render was not
  machine-observable headlessly (SwiftUI resolves literals at render; no
  accessibility introspection) — recorded `MANUAL-ONLY` in the spike. Q7's
  shipped behavior (whole-app re-render via `\.locale`, `Text("literal")`
  compiling to `LocalizedStringResource`) implies it does.
- macOS observability quirk: containerized `open`-launches run the app but
  its stdout / unified-log / Application Support writes never surface to the
  host (one unreproducible full probe report from a non-containerized
  execution). Machine-readable runtime evidence must be captured via the iOS
  simulator's app data container
  (`xcrun simctl get_app_container <udid> app.alanvardy.CheckStitch data`) or
  through a bounded logging channel — never stdout/open.

## Q7 (reference): SingleThread's working app-language mechanism

Repo root `/Users/vardy/dev/SingleThread` — same Xcode 26.x / Swift 6 / iOS
18.7 toolchain, and it ships a six-language UI on iOS + macOS + watch today.
It **never subclasses `Bundle` and never overrides `localizedString`**; the
mechanism is SwiftUI `\.locale` + observable state + explicit resource-locale
resolution.

### Findings
- **Enum** `AppLanguage: String, CaseIterable` (Core): `.system` + six catalog
  languages; `locale` = `.system → .current` (process/device locale), else
  `Locale(identifier: rawValue)`
  (`SingleThreadCore/Sources/SingleThreadCore/AppLanguage.swift:18-19`).
- **State holder** `AppLocaleState` (Core): `@MainActor @Observable`
  process-wide singleton `current`; `init` loads `AppLanguagePreference`
  (validates, unknown → `.system`); `set` persists via `AppLanguagePreference`
  (App Group defaults, key `"appLanguage"`) **and** publishes the `language`
  observable; `effectiveLocale` = `language.locale`; `storedEffectiveLocale`
  (nonisolated static) serves non-View consumers
  (`SingleThreadCore/Sources/SingleThreadCore/AppLocaleState.swift:7-45`).
- **Persistence** `AppLanguagePreference`: `defaultsKey = "appLanguage"`,
  raw string validated against `AppLanguage.allCases` else `.system`
  (`SingleThreadCore/Sources/SingleThreadCore/AppLanguagePreference.swift:16-34`).
- **Live re-render seam = `\.locale`**: the app and watch roots set
  `.environment(\.locale, AppLocaleState.current.effectiveLocale)`
  (`SingleThread/SingleThreadApp.swift:19,44`;
  `SingleThreadWatch/SingleThreadWatchApp.swift:17`). A picker change mutates
  the observable → SwiftUI re-renders the tree → every `Text(...)` /
  `Text("literal")` (all `LocalizedStringResource`) re-resolves against the
  new `\.locale` immediately, no restart.
- **Eager / non-View strings**: `SharedStrings` returns `LocalizedStringResource`
  (lazy, `.module`); callers resolve via `resolved(in: Locale)`, which sets
  `resource.locale = locale` **before** evaluating
  `String(localized: resource)` (the working seam, vs. Q6's parameter form),
  or `resolvedInAppLanguage()` against
  `AppLocaleState.storedEffectiveLocale`
  (`SingleThreadCore/Sources/SingleThreadCore/LocalizedString+Shared.swift:107-117`).
- **Picker wiring**: `SettingsBindings.appLanguage` is store-backed through
  `AppLocaleState.current` (get reads the live holder, set persists +
  republishes — a WatchConnectivity-delivered value updates the picker too)
  (`SingleThread/SettingsBindings.swift:177-188`); the picker renders
  `Text(language.title)` (verbatim endonyms; only `System` is a catalog key)
  and its `.onChange` only fires a preference-changed toast — the binding
  already flipped the observable (`SingleThread/InterfaceSettingsView.swift:63-76`).
- **Watch**: phone choice arrives over WatchConnectivity →
  `service.onAppLanguageReceived = { value in Task { @MainActor in AppLocaleState.current.set(value) } }`
  — live flip, persisted, so a cold launch without the phone keeps it
  (`SingleThreadWatch/WatchAppViewModel.swift:285-291`).
- **Tests**: `SingleThreadTests/AppLanguageTests.swift` and
  `AppLanguageSyncTests.swift` cover resolution and the sync path.

## Cross-Cutting Observations
- **Single-process model**: iOS and macOS are one `MyApp` process with per-OS delegates; a locale override applied at process level on startup would cover both. The watch is a separate `@main` app with its own `.main` catalog and no settings/delegate machinery at all.
- **AppearanceMode is the canonical preference template**: enum keyed in `UserDefaults.standard` via a `*Preference` struct with raw-string validation + fallback, mirrored by an `@AppStorage` prop of the same key whose `onChange` applies the value app-wide through per-platform delegates; tests cover round-trip, unknown-value fallback, and write-back.
- **Settings UI precedent is the appearance `Picker`**: first `Section` of the `Form`, `Picker(selection: $binding)` + `ForEach(allCases)` + `Label(mode.title)`, persisted straight through the `@Binding`→`@AppStorage` chain.
- **Two distinct localization mechanisms already coexist**: app/core strings resolve via `String(localized:)` at render time (process locale), while `InfoPlist.strings` per `.lproj` drive OS-level metadata. Only the former is user-visible UI language.
- **Catalog discipline is enforced exhaustively**: tests require non-empty all six languages for every key in all three catalogs, plus a canary that non-English values actually differ — new UI strings land in the catalogs or those suites fail.

## Open Areas
- **The runtime override mechanism itself** — resolved by the Phase 0 spike: a `Bundle` subclass (isa-swap or override) **cannot** redirect `String(localized:)` on macOS 15 / iOS 18 (Q6). The working alternative is demonstrated by the `SingleThread` reference: SwiftUI `\.locale` environment + an observable `AppLocaleState` (Q7). Catalog readiness is confirmed: `CheckStitch/` already ships compiled `{de,en,es,fr,ja,zh-Hans}.lproj` dirs, and the spike verified the `de` catalog decodes at runtime (`Dunkel`).
- Whether the watch target is in scope: it has no settings surface and no `@AppStorage`; its UI strings are mostly literals, with five catalog keys.
- `InfoPlist.strings` is generated per-language from catalog keys; interplay between a runtime language preference and these OS-level tables is unexamined.
- Watchlist: an interface grouping does not exist in the current Settings `Form` — placement must be decided by Design (following the Q3 mapping of sibling sections).