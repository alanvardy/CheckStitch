# Conventions & Build/Verify Appendix

Shared factual appendix for Design/Structure/Plan. Source: `Makefile`, `scripts/*.sh`, repo `AGENTS.md`, and research reports. All paths repo-relative.

## Canonical commands

| Command | Purpose | Platform/notes |
|---|---|---|
| `bash scripts/test.sh` | **The gate.** `make build` (sim) → headless pre-boot of this worktree's `.simulator_id` UDID (under a bounded host lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock`, `LOCK_TIMEOUT` 60s; missing `.simulator_id` skips pre-boot, unresolvable one is a hard error) → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`; prints `gate: ok`. EXIT trap releases lock and shuts down only the resolved UDID — never `all`/`booted`. | Must pass before work is declared done |
| `make test-unit` | `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, no sim, no signing. Fast pre-gate check. | Unit suites use Swift Testing; XCTest-based suites also run here (VAR-969 store/codec) |
| `make test-ui` | Exactly one `CheckStitchUITests` XCTest smoke via `build-for-testing` → `test-without-building` on this worktree's dedicated simulator (never a bare `name=` destination). | Requires the sim |
| `make build` | Simulator build, scheme `CheckStitch`, destination = `SIM` (explicit) > `.simulator_id` > shared `platform=iOS Simulator,name=iPhone 17` default. | |
| `make build-mac` | Unsigned macOS compile leg (gate's platform check; headless, provisioning-free). | |
| `make build-mac-signed` | Runnable macOS app, team-signed (`DEVELOPMENT_TEAM = 6NWX2DHB9Q`, `-allowProvisioningUpdates`), so `CheckStitch/AppGroup.entitlements` (KVS `com.apple.developer.ubiquity-kvstore-identifier`) embeds and KVS syncs via iCloud. | Used by `run-devices.sh` |
| `make watch-build` | `CheckStitchWatch` compile against watchOS SDK, unsigned, sim-free. | |
| `make run` | Build, then boot/install/launch on the sim (window requested via `open -a Simulator --args -CurrentDeviceUDID <udid>`; honours `--args` only on fresh `Simulator.app` launch). | |
| `bash scripts/run-watch.sh` | Build watch target → install + launch on the paired Apple Watch via `devicectl` (resolves watch by name to an identifier — never a bare name in a destination). | |
| `bash scripts/run-devices.sh` | Install + launch on a real device (Developer Mode; prefers iPhone). Honours `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` overrides. | Keep the plural name — the `r` alias runs it |

Signing constants: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`. macOS slice signs with `CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"` + same entitlements. Do not re-derive from `~/Library/Developer/Xcode`.

## Test-suite inventory

**CheckStitchTests** (Swift Testing `@Test`/`#expect`, macOS-hosted via `-only-testing:CheckStitchTests`; suites opt into `@MainActor` where they touch EventKit/view model — test targets deliberately do NOT set `SWIFT_DEFAULT_ACTOR_ISOLATION`, never restore the app default there):

- `ChecklistCodecTests.swift` — envelope round-trip, v1 `.migratable`, unknown version → empty, `.unsupportedVersion` vs `.unreadable` (`:50-54`), v1-without-`isBlank` decodes (`:25-33`).
- `ChecklistItemTests.swift` — duplicate-title identity (`:6-12`), `isBlank` boundaries (`:14-22`), item Codable round-trip (`:24-28`).
- `ChecklistStoreTests.swift` — persist/reload, corrupt + unsupported-payload handling (`:124-137` not overwritten), text-edit coalescing/flush, rename, deviceID stability, "new payload is version two" (`:328`), mutation stamps, tombstone creation, `apply` merge + idempotence + future-version refusal, duplicate flow (`:522-639`).
- `ChecklistMergeTests.swift` — LWW revision/date/device in either arg order (`:31-49`), tombstone suppression (`:72-131`), distinct-item union (`:111-131`), same-item LWW (`:132-153`), idempotent no-op.
- `ChecklistSyncServiceTests.swift` — seed empty/non-empty, cloud v1 migration, apply remote, merge-and-push, read/write failure, coalescing, unreadable-remote ignored, external-change reconcile.
- `ChecklistSyncMessageTests.swift` — context/runChecklist/request userInfo round-trips, malformed rejection.
- `ChecklistSyncCoordinatorTests.swift` — encoded-context push, store-change push, run-known-id, request re-push, cold-start activation seed.
- `ChecklistViewModelTests.swift` — seeded items, success/denial/failure flags, spinner (legacy core flow).
- `WatchChecklistStoreTests.swift` — activate, context replaces list, malformed context ignored, run/requestRefresh, cold-start refresh, rejected send.
- `EventKitReminderCreatorTests.swift` — construction canary; `ChecklistCreatorTests.swift` — blank-title skipping, denial/failure via `SpyReminderCreator`.
- Platform/UI-adjacent: `ChecklistDetailViewTests.swift` (detail-view pins), `ViewRenderTests.swift`, `LocalizationTests.swift:148` (app usage strings + back-compat pins), `AppearanceModeTests.swift`, `Background*Tests.swift`, `CardPlateTests.swift`, `SettingsBindingsTests.swift`, `ChecklistWidthTests.swift`, `MacWindowFrameTests.swift`, `AboutViewTests.swift`, `AppInfoTests.swift`, `SmokeTests.swift`, `HarnessTests.swift`.
- Fixtures: `TestFixtures.swift` (`makeItem`, `InMemoryChecklistSync`, `FakeChecklistSyncTransport`, `SpyChecklistRunner`, `SpyReminderCreator`), `StubBundle.swift`, `LocalizationFixtures.swift`, `BackgroundTestFixtures.swift`.

**CheckStitchUITests** — one XCTest smoke (`CheckStitchUITests.swift`), iOS simulator, `make test-ui` only.

## Gotchas / conventions

- **Simulator windows**: a running `Simulator.app` attaches a window to every device booted while alive, from any worktree; no headless flag exists. The gate quits `Simulator.app` before the sim-touching part and pre-boots this worktree's UDID.
- **Destination pinning**: bare `name=` destinations are forbidden in scripts (they select a shared device and wedge parallel agents); `SIM=` > worktree `.simulator_id` > shared default.
- **One UI-test process at a time**: `test-ui` uses the dedicated worktree sim; the gate serializes via the host lock.
- **Shell tests**: `scripts/tests/run.sh` stubs `xcrun`/`defaults`/`make`/`open`/`osascript` on `PATH`; run by the gate.
- **Script style**: `#!/bin/bash`, `set -euo pipefail`, committed mode `100755` (`chmod +x` before committing).
- **Swift Testing style**: behaviour-named functions (never `test`-prefixed), `@Test(arguments:)` for cases, `#expect` for assertions, `@MainActor` on suites touching EventKit/the view model.
- **Reference for Reminders/EventKit**: `/Users/vardy/dev/SingleThread` (`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`, `NSReminders*UsageDescription` keys — required because `GENERATE_INFOPLIST_FILE = YES`).