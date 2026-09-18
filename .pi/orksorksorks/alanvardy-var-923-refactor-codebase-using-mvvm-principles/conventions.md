# Conventions — CheckStitch build, test, gate, and suites

Shared factual appendix for Design / Structure / Plan. Reuse instead of
re-opening the Makefile, `scripts/test.sh`, or the test tree.

## Canonical commands
- `make build` — iOS Simulator build (`xcodebuild -scheme CheckStitch -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build`). `Makefile:20`
- `make build-mac` — unsigned headless macOS compile leg (`platform=macOS` + `CODE_SIGNING_ALLOWED=NO`). `Makefile:30`
- `make build-mac-signed` — runnable team-signed macOS app (`-allowProvisioningUpdates`). `Makefile:39`
- `make watch-build` — watchOS Simulator compile of `CheckStitchWatch` (unsigned, sim-free). `Makefile:48`
- `make run` — `build` then `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'`. `Makefile:53`
- `make clean` — `xcodebuild … clean`. `Makefile:63`
- `make test` — `test-unit test-ui`. `Makefile:55`
- `make test-unit` — macOS host, `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests test` (no simulator boot, no signing). `Makefile:60`
- `make test-ui` — `-only-testing:CheckStitchUITests test-without-building` on the dedicated simulator `$(SIM)`. `Makefile:67`
- **The gate is `bash scripts/test.sh`** — order: `make build` → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` (skip with `GATE_TESTS_SKIP=1`) → `shellcheck scripts/*.sh scripts/tests/*.sh` (fallback `bash -n`) → prints `gate: ok`. `scripts/test.sh:116-145`
- Lint: shellcheck only (no swiftlint / no source linter). `scripts/test.sh:137`
- `bash scripts/tests/run.sh` — shell regression tests of the gate/helpers (stubs `xcrun`/`make`/`osascript`/`defaults`).
- SwiftUI SDK verification: **the compiler is the oracle** — edit, then `make build` / `make test-unit`; read `ContentView.swift` precedent before probing SDK modules.

## Destinations / simulator (gotchas)
- `SIM_FROM_WORKTREE` reads `.simulator_id`; `SIM ?=` falls back to `platform=iOS Simulator,name=iPhone 17`. `MAC_SIM := platform=macOS`, `WATCH_SIM := generic/platform=watchOS Simulator`. `Makefile:1-11`
- Simulator resolution precedence: `$SIM` env > `.simulator_id` file; `bash scripts/resolve-sim-udid.sh --require-id "$GATE_DEST"`. A present-but-unresolvable `.simulator_id` is a **hard error**; absent file degrades to shared `name=`. `scripts/test.sh:19-42`
- Gate takes a bounded host lock `$TMPDIR/checkstitch-simulator.lock` (mkdir-based, stale-holder reap, `LOCK_TIMEOUT=60`), quits `Simulator.app` once, pre-boots the worktree UDID headlessly between `make build` and `make test`, shuts down that UDID only (never all/booted) via a single EXIT trap. `scripts/test.sh:47-102,110`
- Never leave a bare `name=` destination in a script — it selects a shared device and wedges parallel agents.

## Signing (gotchas)
- `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`.
- iOS Simulator and `build-mac` legs are unsigned/headless (`CODE_SIGNING_ALLOWED=NO`); only `build-mac-signed`/`run-devices.sh` sign with the development team (embeds `CheckStitch/AppGroup.entitlements`, incl. KVS `com.apple.developer.ubiquity-kvstore-identifier`, enabling `NSUbiquitousKeyValueStore` iCloud sync). On a machine without the profile, add `-allowProvisioningUpdates`. `Makefile:30,39`
- Reference implementation for Reminders/EventKit: `/Users/vardy/dev/SingleThread` (`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`; `NSReminders*UsageDescription` keys — required because `GENERATE_INFOPLIST_FILE = YES`).

## Test-suite inventory
Targets in `CheckStitch.xcodeproj/project.pbxproj`: `CheckStitchTests` (unit-test bundle, dep `CheckStitchCore`, :163-185) and `CheckStitchUITests` (ui-testing bundle, dep `CheckStitchCore`, :187-209). Shared scheme lists both `.xctest` products `parallelizable=NO` in one TestAction (`CheckStitch.xcscheme:49-64`).

### CheckStitchTests (Swift Testing + XCTest; 48 files, each file = one suite)
Frameworks: Swift Testing (majority) `struct XTests { @Test … #expect(...) }`, many `@MainActor struct`; XCTest (minority) `final class XTests: XCTestCase func test…() throws`. `SmokeTests.swift` is the permanent harness/link canary (`@testable import CheckStitchCore`). No `SWIFT_DEFAULT_ACTOR_ISOLATION` on test targets — suites opt in with `@MainActor`.

Platform gating: `#if os(...)`/`#else` inside files (no per-platform files). E.g. `ViewRenderTests.swift:27` macOS `ImageRenderer(...).nsImage` vs `#else` `.uiImage`; `MacWindowFrameTests.swift:7` nests its struct with macOS indirection.

- Fixtures/helpers: `TestFixtures.swift`, `BackgroundTestFixtures.swift`, `StubBundle.swift`, `LocalizationFixtures.swift`, `LocalizationTestHelpers.swift`
- Core domain: `ChecklistItemTests`, `ChecklistItemDateTests`, `ChecklistCreatorTests`, `ChecklistCodecTests`, `ChecklistMergeTests`, `ChecklistWidthTests`, `ChecklistStoreTests`
- Sync: `ChecklistSyncCoordinatorTests`, `ChecklistSyncMessageTests`, `ChecklistSyncServiceTests`, `UbiquitousChecklistSyncTests`, `ReminderListsSnapshotTests`, `WatchChecklistStoreTests`, `ChecklistEntityQueryTests`
- Reminders/EventKit: `ChecklistRemindersTests`, `EventKitReminderCreatorTests`, `EventKitReminderDestinationTests`
- Settings/preferences: `AppearanceModeTests`, `AppearanceModePreferenceTests`, `OrientationPreferenceTests`, `TextSizeTests`, `SettingsBindingsTests`, `SettingsDataActionQueueTests`, `AppLanguageTests`, `AppLanguagePreferenceTests`, `AppLanguageSyncTests`, `InterfaceSettingsViewTests`, `PrivacySettingsContentTests`, `BackgroundFadeTests`, `BackgroundImageStoreTests`, `BackgroundPhotoLayerTests`
- Views/intents: `ViewRenderTests`, `ChecklistDetailViewTests`, `AboutViewTests`, `ExportChecklistsViewTests`, `ListChecklistsIntentTests`, `RunChecklistIntentTests`, `MacWindowFrameTests`, `CardPlateTests`, `ChecklistViewModelTests`, `LocalizationTests`, `LocalizedStringResolutionTests`, `HarnessTests`

### CheckStitchUITests (XCTest UI smoke, one file)
`CheckStitchUITests/CheckStitchUITests.swift`: `final class CheckStitchUITests: XCTestCase`, XCUIAutomation-based. `override class var runsForEachTargetApplicationUIConfiguration: Bool { false }` (:5); `setUpWithError()` with `continueAfterFailure = false` (:7-10); `@MainActor`; asserts accessibility ids `createChecklistButton`/`settingsButton`/`emptyStateCreateButton`/`createRemindersButton` (:13-26); runs `performAccessibilityAudit` (:28-38). Gating: `#if os(iOS)` restricts audit categories to `[.sufficientElementDescription, .trait]`; `#else` (macOS) passes no categories (:31-37).

## Conventions (observed)
- Unit suites behaviour-named functions (never `test`-prefixed); `@Test(arguments:)` for cases; `@MainActor` on any suite touching EventKit or a view model.
- Fakes live in `CheckStitchTests/TestFixtures.swift`.
- View-model tests construct the VM directly with fake stores (mirror precedent: SingleThread `ContentViewModelTests.swift`, `SettingsViewModelTests.swift`, `ReminderDictationTests.swift`, `CompletionGlowTests.swift`).
- UI-testing smoke stays XCTest (never Swift Testing); unit stays Swift Testing.
- Gate verification: `make test-unit` (fast) before the full `bash scripts/test.sh`.