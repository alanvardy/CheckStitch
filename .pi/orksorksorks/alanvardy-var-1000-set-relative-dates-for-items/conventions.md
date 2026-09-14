# Project Conventions

## Canonical commands

- **Gate**: `bash scripts/test.sh` — order: resolve this worktree's simulator UDID (`scripts/resolve-sim-udid.sh`) → take `/tmp/checkstitch-simulator.lock` + pre-boot headlessly → `make build` → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` → shellcheck (fallback `bash -n`); single EXIT trap releases lock and shuts down only the gate's UDID. `LOCK_TIMEOUT` (default 60) bounds the lock wait; missing `.simulator_id` → skip, present-but-unresolvable → hard error; shutdown never `all`/`booted`.
- **Fast loop before the gate**: `make test-unit` — runs `CheckStitchTests` on `platform=macOS` with `CODE_SIGNING_ALLOWED=NO` (no sim, no signing).
- **Targets** (Makefile:15-88): `build` (iOS simulator, scheme `CheckStitch`), `build-mac` (unsigned macOS compile leg — the gate's platform check), `build-mac-signed` (runnable macOS app, dev-team signed, KVS entitlement embedded), `run` (build + `scripts/run-simulator.sh`), `test = test-unit test-ui` (:60), `test-ui` (one `CheckStitchUITests` smoke via build-for-testing → test-without-building, on `SIM`), `watch-build` (scheme `CheckStitchWatch`, `generic/platform=watchOS Simulator`), `clean`.
- **Destination precedence for a simulator** (documented in the Makefile): explicit `SIM=` > this worktree's `.simulator_id` > shared default. **Never leave a bare `name=` destination in a script** — it selects a shared device and wedges parallel agents.
- **Real devices**: `bash scripts/run-devices.sh` (Developer Mode; prefers an iPhone; honours `SCHEME`/`BUNDLE_ID`/`CONFIGURATION`/`DERIVED_DATA`). `bash scripts/run-watch.sh` builds + installs `CheckStitchWatch` and launches on the paired Apple Watch via `devicectl` (watch resolved by name → identifier; never a bare name in a destination).
- **Scripts**: `scripts/*.sh` are `#!/bin/bash`, `set -euo pipefail`, committed mode `100755`. `r` fish alias runs `./scripts/run-devices.sh` (keep the plural name).
- Shell tests: `bash scripts/tests/run.sh`, also run by the gate; stubs `xcrun`/`defaults`/`make`/`open`/`osascript` on `PATH`.

## Test-suite inventory

**Unit suites** run on the **macOS host**, unsigned; **UI smoke** runs on the worktree iOS simulator. Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` — suites opt in per-suite with `@MainActor` (required on anything touching EventKit or the view model); never restore the app's default there. Unit suites import `@testable import CheckStitchCore`.

| Suite | File | Covers | Style / gating |
|---|---|---|---|
| ChecklistItemTests | CheckStitchTests/ChecklistItemTests.swift | stable id for duplicate titles, isBlank, codable round-trip | Swift Testing |
| ChecklistCodecTests | CheckStitchTests/ChecklistCodecTests.swift | envelope round-trip, v1 migratable, unknown→empty, unsupported vs unreadable, v1-without-sync-fields decodes | XCTest-style `func testX` |
| ChecklistMergeTests | CheckStitchTests/ChecklistMergeTests.swift | tombstone union, revision>date>deviceID LWW, tombstones kill, idempotence, LWW both orders | Swift Testing |
| ChecklistStoreTests | CheckStitchTests/ChecklistStoreTests.swift (32 cases) | persistence, rename/name disambiguation, duplicate, text-edit coalescing (300 ms), deviceID stability, revision/timestamp stamps, tombstones, apply/merge/idempotent/refuses-future-version, onChange, envelope round-trip | XCTest-style `func testX` |
| ChecklistSyncServiceTests | CheckStitchTests/ChecklistSyncServiceTests.swift | seed, v1 migration, merge+push, read/write failure, coalesced refreshes, unreadable remote, observer | Swift Testing |
| UbiquitousChecklistSyncTests | CheckStitchTests/UbiquitousChecklistSyncTests.swift | constructs, cancel idempotent | Swift Testing |
| ChecklistSyncMessageTests | CheckStitchTests/ChecklistSyncMessageTests.swift | 3 cases round-trip, unknown key / wrong type rejected | Swift Testing |
| ChecklistSyncCoordinatorTests | CheckStitchTests/ChecklistSyncCoordinatorTests.swift | push context, re-push, runRequest known/unknown ID, activation seeds watch | Swift Testing |
| WatchChecklistStoreTests | CheckStitchTests/WatchChecklistStoreTests.swift | start/context/malformed/run/requestRefresh/activation/cold-drop | Swift Testing |
| ChecklistDetailViewTests | CheckStitchTests/ChecklistDetailViewTests.swift | remove-confirm dialog state, duplicate gated, environment seams — via `String(describing:)` (SwiftUI body can't be staged headless) | Swift Testing, `@MainActor` |
| ChecklistCreatorTests | CheckStitchTests/ChecklistCreatorTests.swift | blank skip, count, all-blank, denial, save-throw (via SpyReminderCreator) | Swift Testing, `@MainActor` |
| EventKitReminderCreatorTests | CheckStitchTests/EventKitReminderCreatorTests.swift | crash-canary: accepts an injected `EKEventStore` | Swift Testing |
| Other pure suites | ViewRenderTests, LocalizationTests, AppearanceModeTests, AppearanceModePreferenceTests, AppInfoTests, BackgroundFadeTests, BackgroundImageStoreTests, BackgroundPhotoLayerTests, CardPlateTests, MacWindowFrameTests, SettingsBindingsTests, ChecklistWidthTests, AboutViewTests, HarnessTests, SmokeTests | app-layer, view/render/localization/appearance | Swift Testing |
| Fixtures | TestFixtures.swift (`SpyReminderCreator`, `sharedTestEventStore`), StubBundle, LocalizationFixtures, LocalizationTestHelpers, BackgroundTestFixtures | shared doubles | — |
| UI smoke | CheckStitchUITests/CheckStitchUITests.swift:13 `testLaunchAndAccessibilitySmoke()` | the only XCTest UI case; runs via `make test-ui` | XCTest, iOS simulator |

Recorded but not independently re-verified this phase: `ChecklistViewModelTests.swift`, `ChecklistSyncCoordinatorTests.swift`, `UbiquitousChecklistSyncTests.swift`, plus the named app-layer suites above (inventory from codebase-locator coverage pass).

## Build/verify gotchas

- **Simulator windows are inevitable while Simulator.app is alive** (every booted device gets a window; no headless flag exists on this toolchain; `com.apple.iphonesimulator AutoOpenDevice` pref is ineffective — spike result). The gate's host lock + EXIT trap is the mitigation; `make run` explicitly requests its window pinned to the resolved UDID (`open -a Simulator --args -CurrentDeviceUDID <udid>`).
- **One simulator consumer at a time** across worktrees: never a bare `name=` destination; always resolve to a UDID (worktree `.simulator_id`).
- **`EKReminder` holds a weak reference to its `EKEventStore`** (ReminderCreating.swift:10-12); a deallocated store crashes (SIGTRAP) on any reminder property read, which is why `sharedTestEventStore` (TestFixtures.swift:34) is session-global. The phone adapter also requires one shared store (EKCADErrorDomain 1021, PhoneSyncAdapter.swift:9).
- **watchOS EventKit is read-only**: the core mirror's save is behind `#if !os(watchOS)` (ReminderCreating.swift:35-37).
- **New app files need no `project.pbxproj` edit** (`PBXFileSystemSynchronizedRootGroup`); the repo carries a committed shared scheme so `xcodebuild test` is deterministic.
- **Signing**: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`, entitlements `CheckStitch/AppGroup.entitlements` (incl. KVS `com.apple.developer.ubiquity-kvstore-identifier`). Without the profile, add `-allowProvisioningUpdates`. macOS slice signs with the same team (`CODE_SIGN_IDENTITY[sdk=macosx*]`). Do not re-derive the team from `~/Library/Developer/Xcode`.
- **Reminders/EventKit reference implementation**: `/Users/vardy/dev/SingleThread` (`EventKitStoring.makeReminder`, `ReminderStore.addReminder`/`rescheduleReminder`, `Calendar.current.dateComponents([.year,.month,.day], from:)`). `GENERATE_INFOPLIST_FILE = YES` requires `NSReminders*UsageDescription` keys.
- **Persisted-state facts** (for anyone touching the wire format): single key `"checklists.v1"` in App Group `UserDefaults` and mirrored `NSUbiquitousKeyValueStore`; envelope `version` is required, everything else `decodeIfPresent`-defaulted; `.unsupportedVersion` payloads lock the local store read-only; tombstones are never GC'd.