# Conventions

## Canonical commands

- **Gate**: `bash scripts/test.sh` — resolves `.simulator_id`/SIM, `make build` (simulator) → headless pre-boot of this worktree's simulator → `make test` (unit + UI) → `make build-mac` (unsigned macOS compile leg) → `make watch-build` (watchOS sim compile) → `scripts/tests/run.sh` (shell tests, stub `xcrun`/`defaults`/`make`/`open`/`osascript`) → `shellcheck scripts/*.sh scripts/tests/*.sh`, printing `gate: ok`.
- `make test-unit` (`Makefile:64-71`): `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO` — no sim, no signing; the fast pre-gate check.
- `make test-ui` (`Makefile:75-86`): exactly one `CheckStitchUITests` smoke via `build-for-testing` → `test-without-building` on this worktree's `.simulator_id` simulator.
- `make test` (`Makefile:60`) = `test-unit test-ui`.
- `make build` — simulator build, scheme `CheckStitch`. `make build-mac` — unsigned macOS compile leg (gate's platform check). `make build-mac-signed` — runnable macOS app signed with `DEVELOPMENT_TEAM = 6NWX2DHB9Q` so `CheckStitch/AppGroup.entitlements` (incl. KVS `com.apple.developer.ubiquity-kvstore-identifier`) embeds; needs `-allowProvisioningUpdates`. `make watch-build` — `CheckStitchWatch` sim compile on watchOS SDK.
- `bash scripts/run-watch.sh` — build watchOS then install+launch on the paired watch via `devicectl` (watch resolved by name → identifier, never a bare name in a destination).
- `bash scripts/run-devices.sh` — real-device install+launch (Developer Mode, prefers iPhone; honours `SCHEME`/`BUNDLE_ID`/`CONFIGURATION`/`DERIVED_DATA`); optional macOS signed build+launch (`RUN_MAC=1` default), so KVS/App Group sync works.

## Test-suite inventory (`CheckStitchTests/`, macOS-hosted unless noted)

| File | Coverage | Gating |
|---|---|---|
| `BackgroundImageStoreTests.swift` | ~17 tests: fetch/store/sidecar, pin gating (`pinBlocksRefreshIfNeeded` :162, `pinnedStoreWithNoImageStillFetches` :190, `repinDuringFetchDoesNotCommit` :205, `forceRefreshBypassesPin` :238, unpin transitions :254/:273/:294), single-flight (`isRefreshingToggledDuringForceRefresh` :151) | `@Suite(.serialized)`; temp-dir injection (`makeStore` :317) |
| `SettingsBindingsTests.swift` | defaults (:18), staged mutation (:23), `makeSettingsBag` snapshot (:28), `writeBack` persistence (:40); round-trips `UserDefaults.standard` | `@Suite(.serialized)`, deferred cleanup (:58) |
| `BackgroundPhotoLayerTests.swift` | decode valid/invalid JPEG (:8, :11), construction with nil/disabled (:14) | `@MainActor`, pure construction, no render |
| `BackgroundFadeTests.swift` | opacity inversion/clamping used by the layer wrapper | — |
| `ViewRenderTests.swift` | `SettingsView` lists all appearance modes (:12), `SyncStatusView` message states (:25-52) | `@MainActor`; constructs views, never renders tree |
| `MacWindowFrameTests.swift` | macOS window frame behaviour | **whole file `#if os(macOS)`** (:1) |
| VAR-969 store/codec XCTest suites | (committed legacy suites) | — |

Fakes: `CheckStitchTests/BackgroundTestFixtures.swift` — `jpegData` 1×1 base64 JPEG (:9), `FakeBackgroundFetcher` (:39), `FetchGate` actor (:56), `GatedBackgroundFetcher` (:88). `TestFixtures.swift:12` `makeIsolatedDefaults()`.

`CheckStitchUITests/CheckStitchUITests.swift`: one XCTest smoke `testLaunchAndAccessibilitySmoke` (:14) with accessibility audit, `runsForEachTargetApplicationUIConfiguration = false` (:8), `#if os(iOS)` gate (:30) for audit categories (bundle compiles for the macOS test phase too).

## Conventions & gotchas

- Unit suites: Swift Testing `@Test`/`#expect`, behaviour-named functions (never `test`-prefixed), `@Test(arguments:)` for cases, `@MainActor` opt-in on any suite touching EventKit or the view model (test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` — never restore the app's default there).
- `Makefile` destination precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared default. **Never** a bare `name=` destination in a script — it selects a shared device and wedges parallel agents.
- Simulator windows: no headless flag exists on this toolchain; the gate takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`), quits `Simulator.app` once before the simulator-touching phase, pre-boots this worktree's UDID, releases the lock after `make test`; missing `.simulator_id` → skip, unresolvable → hard error, shutdown scoped to the resolved UDID only. `LOCK_TIMEOUT` (default 60) bounds the wait; on timeout the gate warns and runs without the lock. `make run` opens the window explicitly (`open -a Simulator --args -CurrentDeviceUDID <udid>`). The `com.apple.iphonesimulator AutoOpenDevice` pref is **ineffective** on this toolchain (Xcode 26.6 / iOS 27.0) — dropped after spike.
- Shell scripts are `#!/bin/bash` with `set -euo pipefail`, committed `100755`. Keep the plural `run-devices.sh` name (the `r` fish alias runs it).
- Signing: bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`, team `6NWX2DHB9Q`; on a machine without the profile add `-allowProvisioningUpdates`. Never re-derive the team from `~/Library/Developer/Xcode`.
- New files under `CheckStitch/` need **no** `project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`); scheme `CheckStitch` committed so `xcodebuild test` is deterministic.
- Reminders/EventKit reference: `/Users/vardy/dev/SingleThread` (`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`; `NSReminders*UsageDescription` keys needed because `GENERATE_INFOPLIST_FILE = YES`).
- `ContentView.swift:1-3` carries a duplicated `import CheckStitchCore` (lines 1 and 3) — harmless but noted (Q2 report).