# Conventions — CheckStitch (repo `/Users/vardy/dev/alanvardy-var-986-add-localizations`)

Dense factual appendix for Design/Structure/Plan. All `file:line` refs are to
this repo unless noted; SingleThread refs are to `/Users/vardy/dev/SingleThread`.

## Build / test / verify commands

| Command | What it runs |
|---|---|
| `make build` | `xcodebuild -scheme CheckStitch -destination '$(SIM)' … build` — iOS Simulator slice (Makefile:19-25) |
| `make build-mac` | same scheme, `-destination platform=macOS`, `CODE_SIGNING_ALLOWED=NO` (Makefile:30-37) — macOS slice, unsigned (App Group entitlement needs a Mac profile; leave unsigned) |
| `make watch-build` | `-scheme CheckStitchWatch -destination generic/platform=watchOS Simulator … build` (Makefile:42-47) — unsigned, sim-free |
| `make test` | `test-unit` + `test-ui` (Makefile:52) |
| `make test-unit` | scheme CheckStitch, `-destination platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests test` (Makefile:57-62) — no sim, no signing |
| `make test-ui` | `build-for-testing` then `-only-testing:CheckStitchUITests test-without-building` on `$(SIM)` (Makefile:65-72) |
| `make run` | build + `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'` (Makefile:49-50) |
| `bash scripts/test.sh` | **the gate** — full ordered run, prints `gate: ok` (scripts/test.sh:1-159) |
| `bash scripts/tests/run.sh` | shell-level regression tests (stubbed PATH), run inside the gate unless `GATE_TESTS_SKIP=1` (scripts/test.sh:144-147) |
| `make clean` | `xcodebuild -scheme CheckStitch -destination '$(SIM)' clean` (Makefile:75) |

`SIM` precedence (Makefile:8-10): explicit `SIM=` env/CLI > this worktree's
`.simulator_id` (`platform=iOS Simulator,id=<udid>`) > `name=iPhone 17` default.
**Never leave a bare `name=` destination in a new script** — it selects a
shared device and wedges parallel agents.

## Gate order (scripts/test.sh)

1. Resolve `GATE_DEST`: `$SIM` env wins, else `.simulator_id` file, else empty (:17-31).
2. `bash scripts/resolve-sim-udid.sh --require-id "$GATE_DEST"` (:34); `.simulator_id` failure = hard error (:36-43).
3. `make build` (:47) — before any simulator window work.
4. Host lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock` via `mkdir` (:58-92): stale-lock reaping by PID, `LOCK_TIMEOUT` default 60s → warn + run unlocked.
5. Single EXIT trap: release lock + `xcrun simctl shutdown "$GATE_UDID"` — **scoped to the resolved UDID, never `all`/`booted`** (:94-117).
6. `osascript -e 'tell application "Simulator" to quit'` (:119) — quits Simulator.app so no window attaches to the pre-booted device.
7. If GATE_UDID: `xcrun simctl boot` + `bootstatus -b` blocking boot (:121-125).
8. `make test` (:128) = macOS unit + simulator UI smoke.
9. `make build-mac` (:132-137) — catches iOS-only-API compiles.
10. `make watch-build` (:139-142) — catches pbxproj/watch-scheme breakage.
11. `bash scripts/tests/run.sh` unless `GATE_TESTS_SKIP=1` (:144-147).
12. `shellcheck scripts/*.sh scripts/tests/*.sh`; else `bash -n` fallback (:149-157).
13. `echo "gate: ok"` (:159).

## Test-suite inventory — `CheckStitchTests/` (23 files, macOS host, unsigned)

Swift Testing (`@Test`, `#expect`, behaviour-named, never `test`-prefixed) except
where noted. Platform gating: deployment-based (whole target runs on macOS);
the only source-level gate is `#if os(macOS)` in `MacWindowFrameTests.swift:1`.
Suites opt into `@MainActor` per-suite (test target sets no default isolation —
never restore the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` in
tests).

- `AppearanceModePreferenceTests.swift` — preference round-trip via isolated UserDefaults.
- `AppearanceModeTests.swift` — `AppearanceMode.load` valid raw values + fallback-to-system.
- `BackgroundFadeTests.swift` — default 50, 10%-steps to 90.
- `BackgroundImageStoreTests.swift` — `@Suite(.serialized)` (:8); fake-fetcher store.
- `BackgroundPhotoLayerTests.swift` — JPEG fixture decode.
- `BackgroundTestFixtures.swift` — fixtures only (1×1 JPEG base64).
- `CardPlateTests.swift` — `CardPlate` fill constants light/dark.
- `ChecklistCodecTests.swift` — XCTest; envelope round-trip.
- `ChecklistCreatorTests.swift` — skips blank titles; delegates reminders to `SpyReminderCreator`; asserts `error.localizedDescription` (:52, :62).
- `ChecklistItemTests.swift` — stable identity for duplicate titles; blank-title rejection.
- `ChecklistStoreTests.swift` — XCTest; fresh uniquely-named UserDefaults suite per test.
- `ChecklistSyncCoordinatorTests.swift` — coordinator with `FakeChecklistSyncTransport`/`SpyChecklistRunner`.
- `ChecklistSyncMessageTests.swift` — message round-trip via userInfo.
- `ChecklistViewModelTests.swift` — view model seeds items.
- `ChecklistWidthTests.swift` — `maxContentWidth` scaling/clamp.
- `EventKitReminderCreatorTests.swift` — crash-canary: real adapter over injected `EKEventStore`.
- `HarnessTests.swift` — trivial `@Suite` sanity.
- `MacWindowFrameTests.swift` — **only `#if os(macOS)`-gated file**; NSRect math.
- `SettingsBindingsTests.swift` — `@Suite(.serialized)` (:6); defaults match preferences.
- `SmokeTests.swift` — canary: app-hosted macOS unit target runs, discovers Swift Testing, links CheckStitchCore.
- `TestFixtures.swift` — `makeItem`/`makeIsolatedDefaults` helpers (no tests).
- `ViewRenderTests.swift` — `SettingsView.body` renders all appearance modes (SwiftUI describe).
- `WatchChecklistStoreTests.swift` — `WatchChecklistStore.start()` activates transport.

`CheckStitchUITests/CheckStitchUITests.swift` — one XCTest smoke
(`testLaunchAndAccessibilitySmoke`); `runsForEachTargetApplicationUIConfiguration = false`;
platform-gated by the `test-ui` Makefile target only.

Fakes for EventKit/reminder work live in `CheckStitchTests/TestFixtures.swift`
(also `BackgroundTestFixtures.swift` for JPEGs).

## Build-system facts (matter for resource/catalog work)

- **Membership = directory sync**: 4 `PBXFileSystemSynchronizedRootGroup`
  (project.pbxproj:62-83) = `CheckStitch/`, `CheckStitchTests/`,
  `CheckStitchUITests/`, `CheckStitchWatch/`; each target declares
  `fileSystemSynchronizedGroups` (:152/:176/:200/:221); all Sources (:305-326)
  and Resources (:282-303) build phases are empty. **Files added under these
  folders are auto-adopted — no pbxproj edit ever needed** (both repos rely on
  this; SingleThread's catalogs/.lproj live inside synced folders with zero
  explicit refs, SingleThread pbxproj:110-149).
- `GENERATE_INFOPLIST_FILE = YES` on every config (app :493/:535; tests
  :573/:598/:622/:646; watch :671/:699) — no physical Info.plist; usage
  descriptions are `INFOPLIST_KEY_*` build settings: app
  `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` /
  `INFOPLIST_KEY_NSRemindersUsageDescription` = `"CheckStitch needs access to create reminders."`
  (:494-495/:536-537). Watch has `INFOPLIST_KEY_CFBundleDisplayName = CheckStitch`
  (:672/:700) + `WKCompanionAppBundleIdentifier` (:673/:701) + `WKWatchOnly = NO`
  (:674/:702).
- App target: `PRODUCT_NAME = "$(TARGET_NAME)"` (:510/:552), no
  `CFBundleDisplayName`; `SUPPORTED_PLATFORMS = iphoneos iphonesimulator macosx`
  (:514/:556).
- String-machine settings (target-identical Debug/Release): app
  `STRING_CATALOG_GENERATE_SYMBOLS = YES` (:513/:555) + `SWIFT_EMIT_LOC_STRINGS = YES`
  (:517/:559); watch `SWIFT_EMIT_LOC_STRINGS = YES` (:688/:710); test targets
  both NO (:580/:605/:629/:653 and :583/:608/:632/:656).
- Project level: `LOCALIZATION_PREFERS_STRING_CATALOGS = YES` (:405/:470);
  `developmentRegion = en` (:258); `knownRegions = (en, Base)` (:260).
- CheckStitchCore package: no `resources:` in `CheckStitchCore/Package.swift`
  (13 lines, tools 6.0, iOS 18.7 / macOS 27.0 / watchOS 26.0, single product+target);
  no Tests/ dir; consumed by all four targets via package dependency
  (project.pbxproj:766-775) — **resources added to the package need
  `resources: [.process("Resources")]`** (SingleThreadCore/Package.swift:17 is
  the reference pattern; bundle is `Bundle.module` from Swift, but tests hosted
  in the app bundle must resolve `<PackageName>_<TargetName>.bundle` from
  `.main` — LocalizationTestHelpers.swift:16-24).
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` only on the app target
  (project.pbxproj:380) — do not add to test targets.

## Gotchas surfaced by research

- **App-hosted unit tests**: `BUNDLE_LOADER = $(TEST_HOST)` (project.pbxproj:248-249/262-263) — localization tests that need the compiled string tables can read them from the test-host app bundle via `.main`; catalog *content* tests can read `.xcstrings` from the source tree via `#filePath` (SingleThread LocalizationTests.swift:15, :227-238 — requires no bundle lookup and works regardless of packaging).
- **Locale-pinning**: SingleThread's `String.en(key, bundle:, table: "Localizable")` helper pins `Locale(identifier: "en")` inside `String(localized:table:bundle:locale:)` (LocalizationTestHelpers.swift:4-10) because host-locale-dependent raw string comparisons are flaky (cf. `SettingsViewTests` there).
- **Display-name localization**: with `GENERATE_INFOPLIST_FILE = YES` and no `INFOPLIST_KEY_CFBundleDisplayName`, a localized `CFBundleDisplayName` comes from `InfoPlist.strings` in each `.lproj` (SingleThread app pattern, SingleThread/de.lproj/InfoPlist.strings); the watch target's hardcoded `INFOPLIST_KEY_CFBundleDisplayName` build setting takes precedence for watch.
- **Usage descriptions stay English at `INFOPLIST_KEY_` level** in the reference project; translations are only in `InfoPlist.strings` (SingleThread app pbxproj:752-754).
- **Plural handling is CLDR-via-xcstrings**: `%lld` keys need `variations.plural` with an `other` category always plus `one` for en/es/de/fr (LocalizationTests.swift:83-109); xcstrings JSON has `stringUnit` vs `variations.plural` shapes (LocalizationTests.swift:20-63).
- **Simulator discipline** (gate): pre-boot between `make build` and `make test`; Simulator.app quit before boot; scoped shutdown of only the worktree UDID in the EXIT trap; lock is host-wide and bounded. A running `Simulator.app` attaches windows to devices booted by other worktrees.
- Shell scripts are `#!/bin/bash` with `set -euo pipefail`, mode `100755`; `shellcheck` runs in the gate, else `bash -n`.
- `ContentView.swift:344` shadows the package `ChecklistWidth` — don't "fix" it while touching strings there; `AppearanceMode` labels exist in both app target and core package (duplicated, both user-facing).