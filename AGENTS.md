# CheckStitch

A small iOS app that turns a list of items into Reminders checklists (one
reminder per item, grouped in a "CheckStitch" reminders list).
Swift/SwiftUI. `CheckStitch/` is the thin app target (views + platform delegates only);
`CheckStitchCore/` is a local sources-only SPM package holding models, the EventKit
seam, the checklist creator and the view model; `CheckStitchTests/` (Swift Testing,
macOS-hosted) and `CheckStitchUITests/` (one XCTest smoke) test them.

## Purpose

- CheckStitch lets a user create "Checklists". Each checklist contains one or
  more "items". Checklists have a name, and each item has a name.
- Running a Checklist creates one reminder for each item in the Reminders
  inbox.
- The app does not delete or complete reminders. It does not edit reminders
  after they have been created. It is only for the purpose of bulk creating
  reminders.

## Layout

- `CheckStitch/MyApp.swift` — app entry point; `CheckStitch/ContentView.swift`
  — the sole screen. New files added under `CheckStitch/` need **no**
  `project.pbxproj` edit: the project uses `PBXFileSystemSynchronizedRootGroup`.
- `CheckStitch/AppGroup.entitlements` — App Group `group.app.alanvardy.CheckStitch`.
- `CheckStitchTests/` — unit suites (Swift Testing, macOS-hosted, plus the
  VAR-969 store/codec XCTest suites); the project also carries a committed
  shared scheme so `xcodebuild test` is deterministic.
- `linear-project.md` — the Linear project to file tickets in (`CheckStitch`).
- `.pi/orksorksorks/<branch>/` — step artifacts; these are committed here.

## Build, run, gate

- `make build` — simulator build (`xcodebuild`, scheme `CheckStitch`).
- `make build-mac` — unsigned macOS compile leg (the gate's platform check;
  no signing, no provisioning).
- `make build-mac-signed` — the runnable macOS app, signed with the
  development team so `CheckStitch/AppGroup.entitlements` (incl. the KVS
  `com.apple.developer.ubiquity-kvstore-identifier`) is embedded and the
  key-value store syncs through iCloud. Used by `run-devices.sh`; needs
  `-allowProvisioningUpdates` (already in the target).
- `make run` — build, then boot/install/launch on a simulator.
- `make watch-build` — watchOS simulator compile of the `CheckStitchWatch`
  target (same `CheckStitchCore` package against the watchOS SDK), unsigned
  and sim-free.
- `bash scripts/run-watch.sh` — build `CheckStitchWatch` for watchOS, then
  install + launch it on the paired Apple Watch via `devicectl` (the watch is
  resolved by name to an identifier — never a bare name in a destination).
- **The gate is `./scripts/test.sh`** — `make build` (simulator) → headless
  pre-boot of this worktree's simulator → `make test` → `make build-mac` →
  `make watch-build` → `scripts/tests/run.sh` →
  `shellcheck scripts/*.sh scripts/tests/*.sh`,
  printing `gate: ok`.
- `make test-unit` runs `CheckStitchTests` on `platform=macOS` with
  `CODE_SIGNING_ALLOWED=NO` (no sim, no signing). `make test-ui` runs exactly one
  `CheckStitchUITests` smoke case via `build-for-testing` →
  `test-without-building` on this worktree's `.simulator_id` simulator.
- Unit tests import `@testable import CheckStitchCore`; the UI smoke stays XCTest.
  Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`, so
  suites opt in with `@MainActor` — never restore the app's default there.
- `bash scripts/run-devices.sh` — install + launch on a real device
  (requires Developer Mode; prefers an iPhone). Honours `SCHEME`,
  `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` overrides.
- Destination precedence is documented in the `Makefile`: explicit `SIM=` >
  this worktree's `.simulator_id` > shared default. Never leave a bare
  `name=` destination in a script — it selects a shared device and wedges
  parallel agents.

## Simulator windows

- **Why windows appear** and the dead ends: see the `simulator` skill.
- **The gate** takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`),
  quits `Simulator.app` once before the simulator-touching part, pre-boots this
  worktree's `.simulator_id` UDID headlessly between `make build` and `make
  test`, then releases the lock after `make test`; the single EXIT trap also
  releases the lock and shuts down that UDID. A lock whose recorded PID is no
  longer alive is reaped as stale. Missing `.simulator_id` → skip; a present
  but unresolvable `.simulator_id` is a hard error; the shutdown is scoped to
  the resolved UDID only — never `all`/`booted`. `LOCK_TIMEOUT` (default 60)
  bounds the lock wait so a slow concurrent gate cannot hang this one; on
  timeout the gate warns and runs without the lock.
- **`make run`** requests its window explicitly, pinned to the resolved UDID
  (`open -a Simulator --args -CurrentDeviceUDID <udid>`). The `--args` are
  honoured on a fresh `Simulator.app` launch; if it is already running, the
  device boot attaches that device's window instead.
- **Shell tests**: `bash scripts/tests/run.sh`, also run by the gate; stubs
  `xcrun`/`defaults`/`make`/`open`/`osascript` on `PATH`.

## Signing

`DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App
Group `group.app.alanvardy.CheckStitch`. On a machine without the profile,
add `-allowProvisioningUpdates`. Do not re-derive the team from
`~/Library/Developer/Xcode` — the values above are the working ones.

The macOS slice signs with the same team (`CODE_SIGN_IDENTITY[sdk=macosx*] =
"Apple Development"`, `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] =
CheckStitch/AppGroup.entitlements`) — the KVS entitlement is what lets
`NSUbiquitousKeyValueStore` sync through iCloud on macOS; the unsigned
`make build-mac` leg exists only so the gate stays provisioning-free.

## Conventions

- Unit suites: `struct <Thing>Tests` in Swift Testing (`@Test`, `#expect`), behaviour-named
  functions (never `test`-prefixed), `@Test(arguments:)` for cases, `@MainActor` on any
  suite touching EventKit or the view model. Fakes live in `CheckStitchTests/TestFixtures.swift`.
- Verify with `make test-unit` (fast) before `bash scripts/test.sh` (full gate).
- SwiftUI API verification: the compiler is the oracle — edit, then `make build`
  / `make test-unit`; read `ContentView.swift`/`CardPlate.swift` precedent before
  SDK probing (see the `swiftui-sdk` skill).
- Sync/icon/render tickets cannot close on static evidence — verify the installed
  bundle on the target and state what the user should see (see `devicectl`).
- `scripts/*.sh` are `#!/bin/bash` with `set -euo pipefail`, committed mode
  `100755` (`chmod +x` before committing). Keep the plural `run-devices.sh`
  name: the `r` fish alias runs `./scripts/run-devices.sh`.
- Reference implementation for Reminders/EventKit work:
  `/Users/vardy/dev/SingleThread` (an `EKReminder` +
  `defaultCalendarForNewReminders()` + `save(commit: true)` pattern, and
  `NSReminders*UsageDescription` keys — required because
  `GENERATE_INFOPLIST_FILE = YES`).
- Step prompts pass `step`, `branch` and `artifact_directory` as **literal
  text, not shell variables** — never `ls "$artifact_directory"`; paste the
  literal `.pi/orksorksorks/<branch>/` path.
