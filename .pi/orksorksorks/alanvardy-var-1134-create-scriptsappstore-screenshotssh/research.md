# Research Findings

## Q1: How does app startup work in `CheckStitch/MyApp.swift` and `CheckStitch/ContentView.swift` — what environment objects and view models are constructed, how is the root screen chosen, and what determines whether the list, empty state, or settings/options screens are shown?

### Findings
- `@main struct MyApp: App` — `CheckStitch/MyApp.swift:8`; iOS delegate adaptor `MyApp.swift:10-12`, macOS adaptor `MyApp.swift:13-15`.
- Nine `@State` objects constructed at declaration: `ChecklistStore`, `ChecklistListViewModel`, `ChecklistRunViewModel`, `SettingsViewModel`, `ChecklistImportExportViewModel`, `BackgroundViewModel`, `AppearanceViewModel`, `ChecklistSyncService`, `PurchaseService`, plus an optional iOS `ChecklistSyncCoordinator` — `MyApp.swift:18-31`.
- `init()` order: `SentryBootstrap.startIfEnabled()` → configure `PurchaseEnvironment.service` → `let store = ChecklistStore()` → `ChecklistSyncService(sync: UbiquitousChecklistSync(), store: store)` + `start()` → construct VMs (`list/run/importExport` take the store; `settings/background/appearance` take none) — `MyApp.swift:40-62`.
- Scene injects `ContentView()` with eight `.environment(...)` values and `.environment(\.locale, AppLocaleState.current.effectiveLocale)`; root is always `ContentView` — `MyApp.swift:87-96` (iOS `:177-185`).
- `.task { await syncService.syncOnLaunch() }`, `.task { await purchaseService.start() }`; iOS-only one-time `ChecklistSyncCoordinator` setup (`MyApp.swift:187-196`); `.onChange` hooks for store lists / language (`:197-214`); `scenePhase` reconcile/flush (`:98-107`, `:216-225`). macOS disables restoration (`:97`).
- `ContentView` reads injected VMs via `@Environment` (`ContentView.swift:5-13`); owns `@AppStorage` appearance/background/text-size/orientation settings (`:21-30`) and `@State private var path: [UUID]` (`:33`).
- Root body ZStack: background colour + `BackgroundPhotoLayer` + `NavigationStack(path: $path)` — `ContentView.swift:44-47`.
- **Empty vs list**: `if listVM.checklists.isEmpty { emptyState } else { checklistList }` — `ContentView.swift:48-62`. `listVM.checklists` is `store.activeChecklists` (`ChecklistListViewModel.swift:17`) and active means `!isArchived` (`ChecklistStore.swift:139`).
- `emptyState` uses `ContentUnavailableView("No checklists")` + `emptyStateCreateButton` — `ContentView.swift:738-771`.
- `checklistList` renders folder sections then loose checklists — `ContentView.swift:486-571`; folder headers `:616-702`.
- **Detail/options** is a push: `.navigationDestination(for: UUID.self) { ChecklistDetailView(checklistID:) }` — `ContentView.swift:140`; rows are `NavigationLink(value: checklist.id)` (`:506`); `createChecklist()` appends a new UUID to `path` (`:812-815`).
- **Settings** is a sheet gated by `settingsVM.showsSettings`; gear calls `settingsVM.begin(from: settingsSnapshot())` (`ContentView.swift:438`, `:468`, macOS toolbar `:106-111`); `SettingsViewModel.begin` stages a bindings bag and sets `showsSettings = true` (`SettingsViewModel.swift:15-23`); sheet body `ContentView.swift:162-168`, write-back `:916-922`, `takeStaged()` handling `:169-188`.
- Other sheets/overlays are driven by VM flags: paywall (`:214-220`), destination prompt (`:266-268`, `:970-992`), prompt-scaling, export/import, share, conflict/folder dialogs (`:224-380`).
- Edit mode (`isEditing`) swaps list rows to reorder/remove and auto-clears when the list empties — `ContentView.swift:380-388`.

## Q2: How are checklists persisted and loaded, and what initialization path would populate the in-memory store at launch?

### Findings
- `@MainActor @Observable final class ChecklistStore` is the single persistence owner — `CheckStitchCore/Sources/CheckStitchCore/ChecklistStore.swift:1,5`.
- `init(defaults: UserDefaults = AppGroup.defaults, key: String = "checklists.v1", textEditDelay: Duration? = .milliseconds(300), now:)` — `ChecklistStore.swift:20-23`.
- `AppGroup.suiteName = "group.app.alanvardy.CheckStitch"`; `defaults` falls back to `.standard` — `AppGroup.swift:6-10`.
- Stable per-install `deviceID` at defaults key `"checklist.deviceID"` — `ChecklistStore.swift:31-38,124`.
- Payload: one `Data` blob under `"checklists.v1"`, written by `defaults.set(ChecklistCodec.encode(envelope), forKey: key)` — `ChecklistStore.swift:799-813`.
- App Group suite covered by `CheckStitchTests/AppGroupTests.swift:9-31`.
- Separate iCloud KVS channel: `ChecklistSyncing` / `UbiquitousChecklistSync` over `NSUbiquitousKeyValueStore.default`, key `"checklists.v1"` — `ChecklistSyncing.swift:20-50`; external-change observer `:35-42`; entitlement in `CheckStitch/AppGroup.entitlements`.
- Codec `ChecklistCodec` at `Checklist.swift:676`, `currentVersion = 6` (`:677`); `encode` JSON (`:698-699`); `classify` probes a `VersionProbe` and yields `.loaded` / `.migratable(from: 1…5)` / `.unsupportedVersion` / `.unreadable` — `Checklist.swift:704-743`.
- Envelope fields `version, deviceID, checklists, tombstones, folders, folderTombstones` with tolerant `decodeIfPresent` — `Checklist.swift:619-672`.
- Load occurs synchronously in `ChecklistStore.init`: `defaults.data(forKey:)` → `classify` → legacy mapping; `.unsupportedVersion` sets `canOverwriteStoredPayload = false` — `ChecklistStore.swift:44-99`.
- `envelope` accessor is the only encoded surface — `ChecklistStore.swift:109-117`.
- Launch path: `MyApp.init()` constructs `ChecklistStore()` then `ChecklistSyncService.start()` (`MyApp.swift:44-63`); service subscribes `store.onChange` + KVS observer (`ChecklistSyncService.swift:43-51`); `syncOnLaunch()` nudges KVS then reconciles and never writes an empty payload (`ChecklistSyncService.swift:99-106,140-151`).
- `scenePhase`: `.active` → `reconcileFromDefaults()`; otherwise `flushPendingSave()` + `pushNow()` — `MyApp.swift:80-90,139-148`.
- Merge path: `apply(remote:)` → `ChecklistMerge` → save; `reconcileFromDefaults()` uses it — `ChecklistStore.swift:728-766,784-797`.
- Phone→watch snapshot uses key `"checklists"` — iOS coordinator `MyApp.swift:104-120`; keys in `ChecklistSync.swift:3-12`.

## Q3: What is the structure and data flow of the watch target — entry point, view models, sync adapter, screens, and data source?

### Findings
- `@main struct CheckStitchWatchApp: App`; `@State viewModel = WatchChecklistViewModel(store: WatchChecklistStore(transport: WatchSyncAdapter()))`; single `WindowGroup` injecting `WatchChecklistListView` + `\.locale` — `CheckStitchWatch/CheckStitchWatchApp.swift:4-13`.
- `WatchChecklistViewModel` wraps the store: exposes `checklists`/`folders`, grouping helpers delegating to `ChecklistGrouping`, `current(_:)`, `onAppear()` → `store.start(); store.requestRefresh()`, `run(_:)`, `visibleItems(of:)`, `phase(runID:)` — `CheckStitchWatch/WatchChecklistViewModel.swift:14-74`.
- `WatchSyncAdapter: NSObject, ChecklistSyncTransport` uses `WCSession.default`; `activate()` guarded by `WCSession.isSupported()`; `sendContext` returns `false`; `sendUserInfo` uses `transferUserInfo` and requires `.activated` — `CheckStitchWatch/WatchSyncAdapter.swift:18-47`.
- Delegate handling: activation reads `receivedApplicationContext` and fires `onMessage`/`onActivated`; `didReceiveApplicationContext` → `receive`; `didReceiveUserInfo` handles `runResult`; `receive` decodes `ChecklistSyncMessage` — `WatchSyncAdapter.swift:50-85`.
- Message/transport/store live in Core: `ChecklistSyncMessage` cases `.context(Data)`, `.runChecklist(id:runID:)`, `.requestChecklists`, `.language(String)`, `.runResult(RunResult)` — `ChecklistSync.swift:115-197`; `ChecklistSyncTransport` protocol `:218-226`; `RunPhase` `:238`; `WatchChecklistStore` `:262`.
- `WatchChecklistStore` is `@MainActor @Observable`, holds `checklists/folders/pendingRuns/phases`; `start()` wires transport callbacks then activates (`:298-307`); `run(_:)` de-dups pending and sends (`:316-328`); `receive(_:)` applies `.context` via `ChecklistCodec.classify`, maps `.runResult`, applies `.language` (`:358-387`).
- Watch data is **not persisted** and never touches EventKit: it only mirrors `.context(Data)` pushed by the phone over `updateApplicationContext`; cold launch reads the already-populated application context; `requestRefresh()` asks the phone to re-push — `ChecklistSync.swift`, `WatchSyncAdapter.swift`.
- Phone-side counterpart `ChecklistSyncCoordinator` handles request/run and sends context/result/language — `CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncCoordinator.swift`.
- Screens:
  - `WatchChecklistListView.swift` — root `NavigationStack` + `List`; empty when `visibleFolders.isEmpty && looseChecklists.isEmpty` → `ContentUnavailableView("No checklists")`; folder rows → `WatchFolderDetailView`; loose rows → `WatchChecklistDetailView`; `.task { viewModel.onAppear() }` (`:5-49`).
  - `WatchFolderDetailView.swift` — members via `viewModel.checklists(in:)`, empty `ContentUnavailableView`, rows to detail (`:9-34`).
  - `WatchChecklistDetailView.swift` — item rows via `visibleItems`, pinned footer "Create reminders" button calling `viewModel.run`, phase gating, localized title — `:1-80`.

## Q4: What launch-argument / environment / process-info handling exists, and how does the single UI test launch the app?

### Findings
- **None exists.** Repo-wide grep for `ProcessInfo`, `CommandLine`, `arguments.contains`, `environment[` over `*.swift` returns no matches; `launchArguments`/`launchEnvironment`/`XCUIApplication` appear only in the UI test.
- Only arg/env-adjacent code is ordinary `UserDefaults.standard` preference persistence: appearance mode (`CheckStitch/AppearanceMode.swift:87`, `CheckStitchCore/.../AppearanceMode.swift:89`), orientation (`CheckStitch/OrientationPreference.swift:8`), crash reporting (`CheckStitchCore/.../CrashReportingPreference.swift:3`), app language (`CheckStitchCore/.../AppLanguagePreference.swift:3`); read back in `CheckStitchTests/SettingsBindingsTests.swift:20-37,63-72`.
- No UI-testing flag, demo seed, empty-state override, or settings-open seam.
- The single UI test `CheckStitchUITests/CheckStitchUITests.swift`, `testLaunchAndAccessibilitySmoke()` (`:12-38`), `@MainActor`, does exactly `let app = XCUIApplication()` (`:14`) and `app.launch()` (`:15`) — no `launchArguments`, no `launchEnvironment`.
- Post-launch assertions: `createChecklistButton` and `settingsButton` exist (`:17-20`); then either `emptyStateCreateButton` or `createRemindersButton` depending on persisted state (`:22-27`); then an accessibility audit under `#if os(iOS)` (`:30-37`).
- `runsForEachTargetApplicationUIConfiguration = false` (`:7`); `continueAfterFailure = false` (`:9-11`).
- UI test runs via `Makefile:92-103`: `build-for-testing` then `test-without-building -only-testing:CheckStitchUITests` on the resolved simulator.

## Q5: How do the existing scripts/*.sh files work — gate driver, simulator helpers, shell test harness/stubs, shellcheck, Makefile targets?

### Findings
- Scripts present: `scripts/test.sh`, `resolve-sim-udid.sh`, `run-simulator.sh`, `run-watch.sh`, `run-devices.sh`, `l10n-check.sh`; harness `scripts/tests/run.sh` (stubs generated at runtime).
- Gate `scripts/test.sh`: `set -euo pipefail`, cd to repo root (`:3-5`); optional disk-clean helper (`:12`); sim resolution `SIM` > `SIM_ID_FILE` (default `.simulator_id`), absent → skip preboot/shutdown (`:14-38`); order `make build` (`:40`) → host lock + quit Simulator window (`:47-95`) → pre-boot own UDID (`:97-103`) → `make test` (`:105`) → `make build-mac` (`:111`) → `make watch-build` (`:115`) → `make widget-build` (`:119`) → `scripts/tests/run.sh` unless `GATE_TESTS_SKIP=1` (`:121-123`) → shellcheck (fallback `bash -n`) over `scripts`, `tests`, `ci_scripts` (`:125-130`) → `gate: ok` (`:132`).
- Lock: `LOCK_DIR=$TMPDIR/checkstitch-simulator.lock`, `LOCK_TIMEOUT` default 60, stale holder PID reaped, single EXIT trap shuts down only the resolved `GATE_UDID` — `test.sh:47-103`.
- `scripts/resolve-sim-udid.sh`: `[--require-id]` + destination; `id=` parsed directly else greps `simctl list` name → UDID (`:9-27`); `--require-id` rejects name form/`not pinned` (`:19-22`) and invalid UUID (`:36-39`); error at `:30`.
- `scripts/run-simulator.sh`: args destination and app path; `BUNDLE_ID` defaults `app.alanvardy.CheckStitch` (`:14-16`); resolves UDID, checks bundle, `simctl boot`, `bootstatus -b`, opens `Simulator` with `-CurrentDeviceUDID`, `simctl install`, `simctl launch --terminate-running-process` (`:20-43`).
- `scripts/run-watch.sh`: env overrides `SCHEME/WATCH_SCHEME/BUNDLE_ID/CONFIGURATION/DERIVED_DATA/WATCH_NAME` (`:18-26`); resolves the watch by name via a Python argv filter over `devicectl list devices -j` (`:38-85`); builds generic watchOS signed with `-allowProvisioningUpdates`, installs and launches via `devicectl` (`:87-110`).
- `scripts/run-devices.sh`: env overrides `SCHEME/BUNDLE_ID/CONFIGURATION/DERIVED_DATA/RUN_MAC/RUN_WATCH` (`:27-32`); discovers iPhones/iPads from `devicectl` JSON, logs unreachable devices and continues (`:47-74+`).
- `scripts/l10n-check.sh`: Python over App/Core/Watch/Widget `xcstrings` for `en de es fr ja zh-Hans`, flags missing/empty/untranslated values honoring `LocalizationFixtures` exclusions, exits 1 (`:12-75`).
- Harness `scripts/tests/run.sh`: `set -euo pipefail`, PASS/FAIL counters and EXIT cleanup (`:4-15`); `new_stubs` creates a temp `PATH` of stub executables logging argv to `$STUB_ROOT/<name>.log` (`:19-34`); `run_case` counts and prints `tests: N passed, N failed` (`:36-46,476`).
- Harness cases: resolver (`:50-101`); gate preboot-skip, shutdown-only-resolved-UDID, lock timeout, invalid sim id, stale-lock reaping, window vs no-window (`:114-203`); run-watch install/launch + unreachable/unknown/typographic (`:231-278`); run-devices watch path and `RUN_WATCH=0` (`:290-358`); macOS sandbox egress awk (`:368-389`); warnings-as-errors project-level guard for `build-mac build test-unit test-ui watch-build widget-build` (`:398-444`); `CFBundleDocumentTypes` (`:448-458`); every script parses with `bash -n` (`:467-474`).
- Makefile: `SIM` precedence `SIM` > `.simulator_id` > `platform=iOS Simulator,name=iPhone 17` (`Makefile:1-5`); targets `build` (`:25-30`), `build-mac` unsigned (`:38-44`), `build-mac-signed` (`:48-54`), `watch-build` generic watchOS sim (`:58-63`), `widget-build` (`:67-72`), `run` (`:74-75`), `test = test-unit + test-ui` (`:77`), `test-unit` macOS-hosted (`:81-88`), `test-ui` build-for-testing/test-without-building (`:92-103`), `clean` (`:105-106`).

## Q6: How is the app language selected at runtime, and how do the six languages map to locale identifiers?

### Findings
- `enum AppLanguage: String, CaseIterable, Sendable` with `.system` plus `.english="en"`, `.german="de"`, `.spanish="es"`, `.french="fr"`, `.japanese="ja"`, `.simplifiedChinese="zh-Hans"` — `CheckStitchCore/Sources/CheckStitchCore/AppLanguage.swift:5-7`.
- `locale`: `.system` → `Locale.current`; otherwise `Locale(identifier: rawValue)` — the raw value **is** the locale id (`AppLanguage.swift:13-17`).
- Presentation titles: `.system` catalog-keyed, six pinned rows render verbatim endonyms — `AppLanguage+Presentation.swift:6-19`.
- Persistence `AppLanguagePreference`: `UserDefaults` key `"appLanguage"` (`:11-14`); validated rawValue, unknown → `.system` (`:17-23`); write `:26-28`.
- `AppLocaleState`: `@MainActor @Observable`, loads from preference (`:14-16`); `static let current` process-wide (`:19`); `nonisolated static storedEffectiveLocale` for non-View callers (`:22-24`); `private(set) var language` (`:28`); `effectiveLocale` (`:30-31`); `set(_:)` persists then updates (`:34-39`).
- Injection: `.environment(\.locale, AppLocaleState.current.effectiveLocale)` at `CheckStitch/MyApp.swift:76,104` and `CheckStitchWatch/CheckStitchWatchApp.swift:13`; settings picker binding `ContentView.swift:829-833`; language-did-change sync `MyApp.swift:130`.
- Non-View resolution seam `LocalizedString+Shared.swift:12-18` (`resolved(in:)` sets resource locale) and `resolvedInAppLanguage()` (`:20-22`), used by intents and `EventKitReminderDestination.swift:73`, `AppInfo.swift:37,41`.
- Four string catalogs (Core, app, watch, widget), `sourceLanguage = en`; `.lproj` dirs for app/watch hold only `InfoPlist.strings`. Language support exactly six pinned ids + `.system`.

## Q7: How does the reference `SingleThread/scripts/appstore-screenshots.sh` work?

### Findings
- Source: `/Users/vardy/dev/SingleThread/scripts/appstore-screenshots.sh`, read in full by the researcher.
- CLI: `scripts/appstore-screenshots.sh [options] [class ...]`; classes `iphone-6.3 | ipad-13 | watch-series11-46mm`; default all three (`L:96-98,600-602`).
- Options: `--fetch-wallpapers`, `--refetch-wallpapers`, `--wallpaper-url`, `--wallpaper-dir`, `--no-build`, `--no-install`, `-h/--help`; unknown `-*` exits 2 (`L:300-337`).
- Env overrides: `REPO_ROOT`, `WALLPAPER_DIR`, `WALLPAPER_API`, `SETTLE` (default 6), `BACKGROUND_IMAGE` (`L:100-125`); `set -euo pipefail` (`L:99`).
- Device map `DEVICE_TYPES`: `iphone-6.3:iPhone 17$` (1206x2622), `ipad-13:iPad Pro 13-inch (M5)` (2064x2752); watch separate `Apple Watch Series 11 (46mm)` (`L:113-115,278-282`).
- `resolve_udid` reads `xcrun simctl list devices available --json`, filters iOS/watchOS family, newest runtime, name regex (`L:339-356`).
- `capture_class` boots + `bootstatus -b`, installs (unless `--no-install`), stages wallpaper, runs per-language shots, shuts down (`L:493-556`); `capture_watch` analogous (`L:585-620`).
- Appearance per shot: `xcrun simctl ui "$UDID" appearance dark|light` (`L:531,537,543,549`).
- Capture `shoot`: terminate, sleep 1, `simctl launch "$UDID" "$BUNDLE" "$@"`, sleep `$SETTLE`, `simctl io screenshot --mask ignored "$out"` (`L:481-491`).
- Seams: iOS `--seed <json>`, `--ui-testing`, `--ui-testing-noop-settle`, `-showSwipePrompt NO`, `--ui-testing-app-language <raw>`, `--ui-testing-open-settings`, `--ui-testing-open-settings-reminder`, `--no-reminders`; watch `--ui-testing-title`, `--ui-testing-notes`, `--ui-testing-open-action-menu`, `--ui-testing-excluded-list Errands`, `--ui-testing-empty`.
- `prime_language` does a throwaway `--ui-testing --ui-testing-app-language` launch because the flag is only read on the `--ui-testing` path; it persists app language into the App Group for the next cold launch (`L:474-479`).
- `SCREENS` defines capture order as `<wallpaper slot>:<output stem>`: main-dark, empty, options (staged twice for the Reminder subscreen), main-light, no-reminders (`L:264-271`).
- Languages `(en zh-Hans fr de ja es)` (`L:224`); `language_folder` maps to `1-en … 6-es` (`L:211-222`); `class_folder` → `1-iphone/2-ipad/3-watch` (`L:230-239`).
- iOS loop per language: seed, prime, six shots with explicit appearance + `stage_slot` (`L:522-552`); watch sets `AppleLanguages`/`AppleLocale` via `simctl spawn defaults write` then reboots before four shots (`L:565-616`).
- Output root `build/appstore-screenshots` (`L:118`), tree `<lang>/<device>/<name>.png` (`L:88`), language-major/device-minor, numeric prefixes give drag order; `rm -rf "$OUT"` at start (`L:604-605`).
- Size verification with `sips` against accepted pairs `1206x2622 | 1179x2556 | 1320x2868 | 2064x2752 | 416x496`; mismatch exits 1 (`L:650-665`).
- Wallpapers: committed fixtures `scripts/fixtures/appstore-wallpapers/` (10 photos + `manifest.json`), keyed by `<class>-<screen>` slot (`L:150-160`); `stage_slot` copies photo to app data container `Library/Application Support/SingleThread/background.jpg` + `background.json`, with a 24h `fetchedAt` guard (`L:438-472`).

## Cross-Cutting Observations
- CheckStitch has **no launch-argument seam anywhere** (Q4), while the reference script is entirely driven by launch arguments (Q7). Every seam the reference relies on (UI-testing mode, language priming, settings-open, empty, seed) has no CheckStitch counterpart.
- The app is dependency-injected at one place (`MyApp.init()`, Q1), and state is persisted before the UI exists via `ChecklistStore()` reading App Group `UserDefaults` synchronously (Q2). Any launch-time seeding therefore has a single interception point before `ContentView` renders.
- Walk vs empty is a pure function of `store.activeChecklists` (Q1); settings is a sheet flag; options/detail requires pushing a checklist UUID. These are three distinct presentation mechanisms, not one route enum.
- Watch data arrives only over WatchConnectivity `.context(Data)` from the phone and is never persisted (Q3); an empty watch shows its own `ContentUnavailableView`.
- App language is persisted in standard `UserDefaults` key `"appLanguage"` and injected as `\.locale`; six ids are exactly `en,de,es,fr,ja,zh-Hans` + `.system` (Q6).
- Scripts are uniformly `#!/bin/bash`, `set -euo pipefail`, mode `100755`, exercised by a stubbed harness; the gate additionally runs `shellcheck` (Q5).
- The reference script's display classes/sizes are iPhone 6.3" (1206x2622), iPad 13" (2064x2752), Watch 46mm (416x496) — not the iPhone 6.9"/6.5" classes named in the ticket.

## Open Areas
- Exact App Store Connect required size pairs for the CheckStitch target classes were not researched from code (no such constants exist in the repo).
- The reference script's wallpaper staging depends on a SingleThread app-side background feature; CheckStitch has `BackgroundPhotoLayer` and `BackgroundViewModel` (Q1) but how its image data is persisted/staged was not traced.
- Watch device-language priming is done by the reference via `simctl spawn defaults write` + reboot; CheckStitch's watch target reads `AppLocaleState.current` (Q6) as well as receiving `.language` messages (Q3), but which path wins at cold launch was not determined.
- `ChecklistStore`'s exact seeding/mutation API surface (create/import methods) was only partially mapped; Q2 covers persistence, not the full mutation API.
