# Conventions

Shared factual appendix for Design/Structure/Plan. Repos: CheckStitch worktree
`/Users/vardy/dev/alanvardy-var-951-get-the-apple-watch-app-running-on-device`;
reference `/Users/vardy/dev/SingleThread`.

## Canonical commands

- **Gate** (only gate; there is **no test target** in CheckStitch): `./scripts/test.sh` = `make build` then `shellcheck scripts/*.sh` (falls back to `bash -n` on scripts).
- `make build` — `xcodebuild -scheme CheckStitch -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build` (Makefile:13-18).
- `make run` — build + `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'` (Makefile:20-21).
- `make clean` — xcodebuild clean with same destination (Makefile:23-24).
- Watch (SingleThread precedent): `make watch-build` (Makefile:29-30), `make watch-test` (104-110), `make watch-ui-test` (96-102) — `xcodebuild -scheme SingleThreadWatch -destination '$(WATCH_SIM)' … build` and tests against `WATCH_TEST_SIM`.
- Destinations: `SIM` = `platform=iOS Simulator,id=<.simulator_id>` if `.simulator_id` present, else `platform=iOS Simulator,name=iPhone 17` (Makefile:4-9). Current `.simulator_id` = `1134601D-40CB-47A1-979B-67D8C14A9221`. Watch: `WATCH_SIM := generic/platform=watchOS Simulator`; `WATCH_TEST_SIM ?= platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)` (xcodebuild needs a concrete device to run XCTests).
- Env overrides honoured by Makefile/scripts: `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` (plus `SIM=` explicit override > `.simulator_id` > default). Never leave a bare `name=` destination in a script — it selects a shared device and wedges parallel agents.
- Simulator launch (`scripts/run-simulator.sh`): resolve `,id=`/`,name=` → UDID via `xcrun simctl list devices available`; `simctl boot` → `simctl bootstatus -b` → `simctl install <UDID> <APP>` → `simctl launch --terminate-running-process <UDID> <BUNDLE_ID>`.
- Device launch (`scripts/run-devices.sh`): `xcrun devicectl list devices -j` + python3 filter (platform iOS, deviceType iPhone/iPad, `developerModeStatus == enabled`; unreachable devices written to `$UNREACHABLE_LOG` and counted as failures); build `-destination 'generic/platform=iOS' -allowProvisioningUpdates`; per device `xcrun devicectl device install app --device <id> <path>` then `device process launch --terminate-existing --activate --device <id> <BUNDLE_ID>`; then unsigned macOS build `platform=macOS CODE_SIGNING_ALLOWED=NO` + `open` (unsigned because the Mac App Group entitlement would need the provisioning profile).

## Test-suite inventory

- **CheckStitch: no tests.** The gate is build + shellcheck (test.sh comment: "no test target"). Do not add a test target as part of a small task.
- **SingleThread watch suites** (reference only):
  - `SingleThreadWatchTests` (unit, Swift Testing `@Test` in `@MainActor` structs — not XCTest): 8 files incl. `ReminderStoreWatchTests.swift` (watchOS store branches, isolated UserDefaults keys), `WatchAppViewModelTests.swift`, `WatchReminderViewModelTests.swift`, `WatchReminderViewRegressionTests.swift:20`, `ShowCompletionGlowStateTests.swift`, `ShowEnableActionButtonsStateTests.swift`, `WatchSyncPipelineTests.swift`, `TestFixtures.swift`.
  - `SingleThreadWatchUITests` (XCTest): `SingleThreadWatchUITests.swift:11` `testLaunchAndRenderSmoke` — launches with `--ui-testing`, asserts seeded content, `performAccessibilityAudit`.
  - Both wired via `TEST_TARGET_NAME = SingleThreadWatch` (`project.pbxproj:1076, :1098`), `SDKROOT = watchos`, run with `-only-testing:` against `WATCH_TEST_SIM`. UI-test seeding via `UITestingSeed.fromLaunchArguments` parsing `--seed '<json>'` (`UITestingSeed.swift:58`).

## Build / verify gotchas

- `GENERATE_INFOPLIST_FILE = YES` (both projects): usage descriptions must be set as build settings — `INFOPLIST_KEY_NSRemindersUsageDescription` / `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` (CheckStitch, project.pbxproj:262-263, :304-305), plus watch keys `INFOPLIST_KEY_WKCompanionAppBundleIdentifier`, `INFOPLIST_KEY_WKWatchOnly` (SingleThread pbxproj:950-952, :978-980).
- Watch target config recipe (SingleThread pbxproj:940-1016): `SDKROOT = watchos`, `SUPPORTED_PLATFORMS = "watchos watchsimulator"`, `TARGETED_DEVICE_FAMILY = 4`, `WATCHOS_DEPLOYMENT_TARGET = 26.5` (CheckStitch project-level is 27.0; SingleThread's package declares watchOS 26.5), `PRODUCT_BUNDLE_IDENTIFIER` suffixed `.watchkitapp`, `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, `CODE_SIGN_STYLE = Automatic`, `SKIP_INSTALL = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. **No `CODE_SIGN_ENTITLEMENTS` on watch configs** in SingleThread — team-based automatic signing; the entitlements file is only for iphoneos*/iphonesimulator* (and widget) configs.
- Watch sources need no pbxproj file entries: `PBXFileSystemSynchronizedRootGroup` with `path = SingleThreadWatch` pulls the whole directory (pbxproj:126-130, :328-330). Same mechanism in CheckStitch for `CheckStitch/`.
- `xcrun simctl` uses `simctl help <subcommand>` — `simctl --help` is rejected. `<device>` is a UDID or the special `booted` string.
- `xcrun devicectl` identity strings: `uuid|ecid|serial_number|udid|name|dns_name`. Error 4016 = device offline / RDS off; reachability from JSON `transportType`/`tunnelState`. On machines without the provisioning profile add `-allowProvisioningUpdates`.
- Devices on this machine: real watch `Alan's Apple Watch` (`00008301-209B793C010BC02E`, Apple Watch Ultra, paired, available); watch sims `Apple Watch Series 11 (46mm)` `3F69EA19-301C-4978-AA7B-A63DE7CE69F5`, `CI Watch S11-local` `812D7CCA-9A0A-4E56-BB38-F5EE8CCE0935`, `LocalTest Watch` `F12FB67A-8E5D-45AE-9018-87E841071B9F`; `simctl pair <watch> <phone>` exists for sim pairing.
- EventKit on watchOS is **read-only**: the shared store compiles out `save`/`remove`/`makeReminder`/`refreshSourcesIfNecessary` behind `#if !os(watchOS)` (`EventKitStoring.swift:34-37`) and relays mutations via hooks/WatchConnectivity. CheckStitch's iOS flow is `EKEventStore()` → `requestFullAccessToReminders()` → `EKReminder(eventStore:)` → `calendar = defaultCalendarForNewReminders()` → `save(commit: true)` (`ContentView.swift:86-105`).
- Scripts are `#!/bin/bash` with `set -euo pipefail`, committed `100755`. Gate also runs `shellcheck` (fallback `bash -n`).
- `EKCADErrorDomain Code=1021` (EventKit per-process connection cap): test seams share one process-wide `EKEventStore` (`InMemoryEventStore.swift:95-101`).