# Research Findings

Paths relative to `/Users/vardy/dev/alanvardy-var-986-add-localizations` unless
noted. SingleThread paths relative to `/Users/vardy/dev/SingleThread`.

## Q1: iOS/macOS app target — user-facing copy and localization-relevant build config

### Findings
- User-facing strings, per file (literal counts, app target `CheckStitch/`):
  - `ContentView.swift` — 8: `"Create checklist"` accessibility label L151 & Label L158, `"Settings"` L188/L196/L198, `"No checklists"` L253, `"Create a checklist to turn its items into reminders."` L255, `Button("Create checklist")` L257, `"Create reminders from checklist"` L279.
  - `ChecklistDetailView.swift` — 12: `Section("Checklist name")` L23, `TextField("Name")` L24, `TextField("Item")` L29, `Label("Add Item")` L39, `Label("Remove Checklist")` L49, `.navigationTitle("Edit checklist")` L55, `Button("Done")` L59, alert `"Name already in use"` L80 + `"OK"` L81 + body L84, `ContentUnavailableView("Checklist not found")` L89.
  - `BackgroundSettingsView.swift` — 10: `"Background"`/caption L14-15, `"\(percent)%"` L25, `"Background Fade"` L29-30, `"Pin wallpaper"` L39-40, `"Refresh wallpaper"` L54, `"Photo by … on Unsplash"` L67, `.navigationTitle("Background")` L76.
  - `SettingsView.swift` — 6: `"Appearance"` L24, caption L25, `Label("Background")` L39, `.navigationTitle("Settings")` L44, `"Done"` L48, preview `"Dark"` L72.
  - `ChecklistStore.swift` — defaults: `create(name: "New checklist")` L65, `ChecklistItem(title: "New item")` L112, dedup `"\(base) \(suffix)"` L97; storage key `"checklists.v1"` L31 (not user-facing).
  - `AppearanceMode.swift` — picker labels `"System"/"Light"/"Dark"` L71-73; SF Symbol names L62-64 (not localized).
- Zero-literal files (verified): `MyApp.swift`, `SettingsBindings.swift`, `SettingsSubscreenLayout.swift`, `CardPlate.swift`, `BackgroundFade.swift`, `Color+CrossPlatform.swift`, `CheckStitchButtonModifier.swift`, `AppDelegate.swift`.
- **Resource membership is directory-synchronized**: only built products have file refs; sources/resources have no PBXBuildFile/BXFileReference entries. `PBXFileSystemSynchronizedRootGroup` `CheckStitch` (project.pbxproj:62-66) is the only membership mechanism (app target declaration :152). All four `PBXResourcesBuildPhase` are empty (`files = ()`, :282-303) and all four `PBXSourcesBuildPhase` are empty (:305-326). **Any `.xcstrings` or `.lproj` dropped under `CheckStitch/` is auto-picked-up by the sync group with no pbxproj edit** (Q1 report; same mechanism shown by SingleThread Q4).
- Build settings (Debug :479-518, Release :521-560 — textually identical; app target `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx` :514):
  - `GENERATE_INFOPLIST_FILE = YES` :493/:535 (also YES on tests :573/:598/:622/:646 and watch :671/:699).
  - `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` and `INFOPLIST_KEY_NSRemindersUsageDescription` = `"CheckStitch needs access to create reminders."` :494-495/:536-537 (English-only build-setting values).
  - `PRODUCT_NAME = "$(TARGET_NAME)"` :510/:552; **no `CFBundleDisplayName` / `CFBundleName` override on the app target** (display name defaults to product name).
  - `STRING_CATALOG_GENERATE_SYMBOLS = YES` :513/:555 (NO on both test targets :580/:605/:629/:653); `SWIFT_EMIT_LOC_STRINGS = YES` :517/:559 (NO on tests :583/:608/:632/:656).
  - `MARKETING_VERSION = 1.0`, `PRODUCT_BUNDLE_IDENTIFIER = app.alanvardy.CheckStitch`, `CURRENT_PROJECT_VERSION = 1`.
- Project-level (Debug :398-419, Release :463-486): `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` :405/:470; `STRING_CATALOG_GENERATE_SYMBOLS = YES` :411/:475; `developmentRegion = en` :258; `knownRegions = (en, Base)` :260 (languages not yet registered).
- Watch embedding: `PBXCopyFilesBuildPhase "Embed Watch Content"` :48-61 copies `CheckStitchWatch.app` into `$(CONTENTS_FOLDER_PATH)/Watch`, `platformFilter = ios` — packaging, not localization.

## Q2: CheckStitchCore SPM package

### Findings
- `CheckStitchCore/Package.swift` (13 lines): swift-tools-version 6.0 (:1); platforms `.iOS("18.7")`, `.macOS("27.0")`, `.watchOS("26.0")` (:7-11); one product `.library(name: "CheckStitchCore", targets: ["CheckStitchCore"])` (:12-14); one target (:15-17); **no `resources:` key anywhere**; no `Tests/` dir (tested only via app-hosted `@testable import`).
- User-facing/fallback text in `CheckStitchCore/Sources/CheckStitchCore/`:
  - `Checklist.swift:23` — default name `"New checklist"` (init default); `:70/:76` logger messages (not UI).
  - `ChecklistViewModel.swift:15` — default editable name `"checklist"`; `:16-18` seeded row titles `"one"`/`"two"`/`"three"`; `:43` logger.message (not UI).
  - `AppearanceMode.swift:67-71` — **human-readable picker labels `"System"`, `"Light"`, `"Dark"`** (also duplicated on the app side at `CheckStitch/AppearanceMode.swift`); `:60-64` SF Symbol names; `:102` UserDefaults key; `:106-108` rawValue fallback `"system"`.
- No user-facing literals: `ChecklistCreator.swift` (returns `error.localizedDescription` :31), `ReminderCreating.swift`, `ChecklistSync.swift` (protocol dict keys :7-9), `ChecklistSyncCoordinator.swift`, `ChecklistWidth.swift`, `Environment.swift`.
- Consumption: `XCLocalSwiftPackageReference` `relativePath = CheckStitchCore` (project.pbxproj:766-768, packageReferences :266-268); `XCSwiftPackageProductDependency` productName CheckStitchCore (:773-775); **all four targets** (app :159, tests :183, UITests :207, watch :228) declare `packageProductDependencies`; `import CheckStitchCore` in 6 app files + 4 watch files.
- Note: `CheckStitch/ContentView.swift:344` defines a local `enum ChecklistWidth` shadowing the package type; `ContentView.swift:214` calls `ChecklistWidth.maxContentWidth`.

## Q3: CheckStitchWatch target

### Findings
- 4 source files; only 2 carry user-facing copy:
  - `WatchChecklistListView.swift:17` — `ContentUnavailableView("No checklists", …, description: Text("Open CheckStitch on your iPhone."))`; `:23` `.navigationTitle("Checklists")`.
  - `WatchChecklistDetailView.swift:26` — `Button(sent ? "Sent" : "Create reminders")`; `:29` `.navigationTitle(checklist.name)` (data-driven).
  - `CheckStitchWatchApp.swift:5` — `@main` entry (`WindowGroup → WatchChecklistListView`, :9-12); no copy. `WatchSyncAdapter.swift` — comments only.
- Config (Debug :664-691, Release :692-707; `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = watchos watchsimulator` :686/:708; `WATCHOS_DEPLOYMENT_TARGET = 26.0` :690/:709; `TARGETED_DEVICE_FAMILY = 4` :689):
  - `GENERATE_INFOPLIST_FILE = YES` :671/:699; `PRODUCT_NAME = "$(TARGET_NAME)"` :678/:706; bundle id `app.alanvardy.CheckStitch.watchkitapp` :677/:705.
  - `INFOPLIST_KEY_CFBundleDisplayName = CheckStitch` :672/:700 — **the only display-name override in the project**.
  - `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch` :673/:701; `INFOPLIST_KEY_WKWatchOnly = NO` :674/:702.
  - `SWIFT_EMIT_LOC_STRINGS = YES` :688/:710 (no `STRING_CATALOG_GENERATE_SYMBOLS` on watch).
  - No iOS-only INFOPLIST keys (scene manifest/UILaunchScreen/orientations only on the iOS target).
- Membership: same `PBXFileSystemSynchronizedRootGroup` `CheckStitchWatch` (project.pbxproj:79-81, target decl :221-223); Resources phase empty (:298-302).

## Q4: SingleThread localization, end to end (reference)

### Findings
- **Catalogs** (`Localizable.xcstrings`, `sourceLanguage: "en"`), one per target:
  - App `SingleThread/Resources/Localizable.xcstrings` — 137 keys; Watch `SingleThreadWatch/Resources/Localizable.xcstrings` — 7; Widget `SingleThreadWidget/Resources/Localizable.xcstrings` — 5; Core `SingleThreadCore/Sources/SingleThreadCore/Resources/Localizable.xcstrings` — 33.
  - All four catalogs carry **the same 6 languages per string: en, de, es, fr, ja, zh-Hans** (verified).
- **`.lproj` sync dirs**: 6 per app-side target (`SingleThread/`, `SingleThreadWatch/`, `SingleThreadWidget/` each have `en,de,es,fr,ja,zh-Hans.lproj`); the Core SPM package has **no** `.lproj` dirs.
- **String abstractions**:
  - `String(localized:table:bundle:)` is dominant: app `bundle: .main` (`SingleThreadApp+Commands.swift:17,23`, `ContentView.swift:697,722`, `CreationFeedback.swift:29`); core `bundle: .module` (`ReminderRecurrenceFormatter.swift:17-30`, `ReminderSkip.swift:42-44`, `LocalizedString+Shared.swift:16-98` — `enum SharedStrings` wrapping ~20 core strings, all `table: "Localizable", bundle: .module`).
  - `LocalizedStringResource("Next Thing", table: "Localizable", bundle: .main)` — `SingleThreadWidget/NextThingWidget.swift:109,111`.
  - `LocalizedStringKey(SharedStrings.reminder)` — `SingleThread/SettingsView.swift:90,121`.
- **Resource declaration**: same synchronized-folder mechanism as CheckStitch — app/watch/widget `PBXFileSystemSynchronizedRootGroup` (project.pbxproj:110-149), all Resources phases empty (:478-523), pbxproj never names `Localizable.xcstrings` or `.lproj`. Widget has one membership exception (member-ship exceptions :101-107/:133-137 exclude `Info.plist`). Core declares `resources: [.process("Resources")]` in `SingleThreadCore/Package.swift:17`.
- **Catalog-related settings**: `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` (pbxproj:670,727); `STRING_CATALOG_GENERATE_SYMBOLS = NO` on **every** SingleThread config (:774,824,849,878,906,930,958,986,1018); project `developmentRegion = en` :445, `knownRegions = en, Base, zh-Hans, es, ja, de, fr` :447-455.
- **Localized InfoPlist.strings** (`<lang>.lproj/InfoPlist.strings`, `PropertyListSerialization`-parseable): app en localizes `NSMicrophoneUsageDescription`, `NSRemindersUsageDescription`, `NSSpeechRecognitionUsageDescription`, `CFBundleDisplayName = "SingleThread"`; de translates the 3 usage strings, keeps `CFBundleDisplayName`; watch en localizes `NSRemindersFullAccessUsageDescription` + `CFBundleDisplayName`; widget lproj (all 6) contain only `CFBundleDisplayName`.
- **App display-name mechanics**: app target `GENERATE_INFOPLIST_FILE = YES` with **no** `INFOPLIST_KEY_CFBundleDisplayName` → localized name comes from `InfoPlist.strings` into the generated plist. Watch/widget keep `INFOPLIST_KEY_CFBundleDisplayName` build settings. Hardcoded English usage descriptions remain at the `INFOPLIST_KEY_` level; translations live only in `InfoPlist.strings`.

## Q5: SingleThread localization tests

### Findings
- `SingleThreadTests/LocalizationTests.swift` — `struct LocalizationTests` (:17), 5 `@Test` funcs + helper section (:179). **Catalogs are read from the source tree via `#filePath`-derived filesystem URLs, not from a Bundle** (:15, :227-238).
  - `catalogsParseAndHaveNonEmptyEnglish` (:20-63): JSON-parses each catalog, asserts every key has `localizations["en"]`, `stringUnit.value` non-empty (or all plural `variations.plural` categories non-empty).
  - `catalogsHaveAllSixLanguages` (:65-81): every key resolves non-empty in each of `languages = ["en","zh-Hans","es","ja","de","fr"]` (:196).
  - `pluralKeysCarryPluralVariationsInAllLanguages` (:83-109): every `%lld` key must carry `variations.plural` in every language, always `.contains("other")`, plus `.contains("one")` when language ∈ `pluralLocales = ["en","es","de","fr"]` (:182). `pluralKeys` :184-190 (Core "Every %lld days/weeks/months/years", App "You have %lld reminders waiting — open SingleThread!").
  - `infoPlistStringsHaveRequiredKeysPerLanguage` (:111-126): for each target × language, path `<repoRoot>/<target>/<lang>.lproj/InfoPlist.strings`, parses `PropertyListSerialization`, asserts every required key present and non-empty. `infoPlistTargets` :240-247 (app: 3 usage descriptions + `CFBundleDisplayName`; watch/widget: `NSRemindersFullAccessUsageDescription` + `CFBundleDisplayName`).
  - `nonEnglishValuesDifferFromEnglish` (:128-175, applies to Core+App only via `guardedCatalogs` :251-253): non-English values must differ from English unless the key is an `excludedIdentities` exception (:257-275, e.g. `%lld%%`, app name, copyright, "System" de, "Version %@" de/fr); "Medium" deliberately NOT excluded (:278-280).
- `SingleThreadTests/LocalizationTestHelpers.swift`:
  - `String.en(_ key: LocalizationValue, bundle: Bundle, table: String = "Localizable") -> String` (:4-10) — pins `locale: Locale(identifier: "en")` inside `String(localized:table:bundle:locale:)` for host-locale-independent assertions.
  - `Bundle.core` (:16-24) — resolves `"SingleThreadCore_SingleThreadCore.bundle"` from `.main` with `preconditionFailure` on absence; doc (:13-15) documents the Swift-package resource-bundle naming `<PackageName>_<TargetName>.bundle` and why tests cannot use `Bundle.module` (it resolves to the package bundle, not the embedded app bundle).
- Wider `String.en` usage (all `table: "Localizable"`): `SingleThreadTests.swift`, `SortOptionTests`, `AppearanceModeTests`, `TextSizeTests`, `ReminderRecurrenceFormatterTests`, `ReminderIntentsTests`, `ReminderSkipTests`, `AppInfoTests`, `PrivacySettingsContentTests.swift:29-31` — pattern: `.core` for Core strings, `.main` for app strings.
- `SettingsCaptionTests.swift` / `SettingsViewTests.swift` are not bundle-driven (raw `String(describing:)` literal comparisons); `StubBundle.swift` stubs `infoDictionary` for `AppInfoTests` only.

## Q6: CheckStitch tests and gate plumbing

### Findings
- **Test inventory** (see conventions.md for the flat list): 23 files in `CheckStitchTests/` (Swift Testing with XCTest exceptions — `ChecklistCodecTests`, `ChecklistStoreTests` are XCTest; 2 fixture-only files). One file is whole-file platform-gated: `MacWindowFrameTests.swift` wraps everything in `#if os(macOS)` (`:1`). Remaining gating is deployment-based: the CheckStitchTests target runs `-destination platform=macOS`, unsigned (`Makefile:41-47`), `BUNDLE_LOADER = $(TEST_HOST)` (project.pbxproj:248-249/:262-263). `@Suite(.serialized)` in `BackgroundImageStoreTests.swift:8` and `SettingsBindingsTests.swift:6`. Suites opt into `@MainActor` per-suite (test target sets no default isolation). `CheckStitchUITests/CheckStitchUITests.swift` — one XCTest smoke (`testLaunchAndAccessibilitySmoke`).
- **Gate order** (`scripts/test.sh:1-159`): resolve `GATE_DEST` (`$SIM` env > `.simulator_id` > none, :17-31) → resolve UDID via `scripts/resolve-sim-udid.sh --require-id` (:34; `.simulator_id`-sourced failure is a hard error :36-43) → `make build` (:47) → host lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock` (:58-92, stale-PID reaping, `LOCK_TIMEOUT` default 60s, timeout warns and runs unlocked) → single EXIT trap releases lock + `simctl shutdown` scoped to resolved UDID (:94-117) → `osascript` quits `Simulator.app` (:119) → pre-boot `simctl boot` + `bootstatus -b` (:121-125) → `make test` (:128) → `make build-mac` (:132-137) → `make watch-build` (:139-142) → `bash scripts/tests/run.sh` unless `GATE_TESTS_SKIP=1` (:144-147) → `shellcheck scripts/*.sh scripts/tests/*.sh` else `bash -n` (:149-157) → `echo "gate: ok"` (:159).
- **`scripts/tests/run.sh`**: PATH-stubbed regression tests (stub executables logging argv, :26-41) for `resolve-sim-udid.sh` (5 cases :49-84), gate lock/pre-boot/shutdown behavior (:104-158), `run-simulator.sh` window behavior (:183-190), `run-watch.sh` (:232-260); PASS/FAIL tally (:292-293).
- **Membership**: 4 `PBXFileSystemSynchronizedRootGroup` (project.pbxproj:62-83) = CheckStitch/CheckStitchTests/CheckStitchUITests/CheckStitchWatch; targets declare `fileSystemSynchronizedGroups` (:152/:176/:200/:221); Sources (:305-326) and Resources (:282-303) phases all empty; explicit refs only for built products and the CheckStitchCore framework product; `Embed Watch Content` copy phase on the iOS app target (:41-53). `PBXProject` :234-280 wires all 4 targets to package `CheckStitchCore`.

## Cross-Cutting Observations

- **Both projects use the same membership mechanism**: Xcode 16 synchronized root groups with empty explicit phases — new resource files (`.xcstrings`, `.lproj`) require **no pbxproj edits** in either repo; the folder IS the project.
- **Reference-handling of app name in CheckStitch differs from SingleThread**: SingleThread's app target has no `CFBundleDisplayName` build setting and localizes the name via `InfoPlist.strings`; CheckStitch's app target likewise has none (so the same InfoPlist.strings path works), while its **watch** target hardcodes `INFOPLIST_KEY_CFBundleDisplayName = CheckStitch`.
- **Setting split between the repos**: CheckStitch app/watch set `STRING_CATALOG_GENERATE_SYMBOLS = YES` and `SWIFT_EMIT_LOC_STRINGS = YES` (tests NO/NO) and already has `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` + `developmentRegion = en`; SingleThread sets `STRING_CATALOG_GENERATE_SYMBOLS = NO` everywhere and registers the 6 languages in `knownRegions`. CheckStitch's `knownRegions = (en, Base)` today.
- **String surface is small and enumerable**: app-side views ~39 user-facing literals + `ChecklistStore` defaults; core ~4 (labels + defaults); watch 5. The ticket's ~170 figure counts all quoted literals including SF Symbols, accessibility identifiers, storage keys and logs.
- **Managerial duplication**: `AppearanceMode` labels ("System"/"Light"/"Dark") exist in both the app target (`CheckStitch/AppearanceMode.swift:71-73`) and the core package (`CheckStitchCore/.../AppearanceMode.swift:67-71`); the app's `ContentView.swift:344` shadows the package `ChecklistWidth` type.
- **Test convention for localized output** (SingleThread): locale-pinned `String.en(key, bundle:, table:)` helper; a `Bundle.core`-style resolver using the `<PackageName>_<TargetName>.bundle` name in the app bundle; catalog-parse tests reading `.xcstrings` from the repo tree via `#filePath`; per-target InfoPlist.strings key-presence tests via `PropertyListSerialization`; plural catalogs need `variations.plural` with `other` (+`one` for en/es/de/fr).
- **Usage descriptions stay English at the build-setting level** in SingleThread; translations are supplied exclusively through `InfoPlist.strings` — a pattern that maps directly onto CheckStitch's existing `INFOPLIST_KEY_NSReminders(FulllAccess)UsageDescription` values (`"CheckStitch needs access to create reminders."`).

## Open Areas

- Exact per-key count of CheckStitch user-facing strings is heuristic (the cited literals are verified; unticked non-UI literals like SF Symbols/accessibility ids were not exhaustively enumerated by the researchers — a full inventory belongs to the Design phase).
- Whether the generated-Info.plist path prefers `INFOPLIST_KEY_*` build settings or `InfoPlist.strings` when both exist was inferred from SingleThread's working pattern, not experimentally verified on this Xcode toolchain.
- Localized widget targets do not exist in CheckStitch, so the widget-specific patterns (physical `Info.plist` + membership exceptions, `LocalizedStringResource` in widget extension context) have no CheckStitch analogue.
- Accessibility-label and preview strings appear in the inventory but were not categorized separately; whether Xcode extracts them into a separate `Localizable` extraction pass was not verified.