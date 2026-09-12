# CheckStitch

A small iOS app that turns a list of items into Reminders checklists (one
reminder per item, grouped in a "CheckStitch" reminders list).
Swift/SwiftUI. `CheckStitch/` is the thin app target (views + platform delegates only);
`CheckStitchCore/` is a local sources-only SPM package holding models, the EventKit
seam, the checklist creator and the view model; `CheckStitchTests/` (Swift Testing,
macOS-hosted) and `CheckStitchUITests/` (one XCTest smoke) test them.

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
- `make run` — build, then boot/install/launch on a simulator.
- The gate pre-boots this worktree's `.simulator_id` device headlessly before
  `make test` and shuts it down on exit (scoped to that UDID only — never
  `all`/`booted`). If `.simulator_id` is missing it skips pre-boot entirely and
  never selects a shared device.
- A running `Simulator.app` attaches a window to every booted device, and the
  `AutoOpenDevice` preference proved ineffective on this toolchain (Xcode 26.6,
  spike in Phase 1 of the implement plan). The gate therefore takes a bounded
  host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`) and quits
  `Simulator.app` around the simulator-touching part. Shell-level regression
  tests live in `scripts/tests/run.sh` and run as part of the gate.
- **The gate is `./scripts/test.sh`** — `make build` (simulator) → `make test` →
  `shellcheck scripts/*.sh`, printing `gate: ok`.
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

## Signing

`DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App
Group `group.app.alanvardy.CheckStitch`. On a machine without the profile,
add `-allowProvisioningUpdates`. Do not re-derive the team from
`~/Library/Developer/Xcode` — the values above are the working ones.

## Conventions

- Unit suites: `struct <Thing>Tests` in Swift Testing (`@Test`, `#expect`), behaviour-named
  functions (never `test`-prefixed), `@Test(arguments:)` for cases, `@MainActor` on any
  suite touching EventKit or the view model. Fakes live in `CheckStitchTests/TestFixtures.swift`.
- Verify with `make test-unit` (fast) before `bash scripts/test.sh` (full gate).
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
