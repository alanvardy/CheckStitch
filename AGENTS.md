# CheckStitch

A small iOS app that turns a list of items into Reminders checklists (one
reminder per item, grouped in a "CheckStitch" reminders list). Swift/SwiftUI,
one app target, no dependencies.

## Layout

- `CheckStitch/MyApp.swift` — app entry point; `CheckStitch/ContentView.swift`
  — the sole screen. New files added under `CheckStitch/` need **no**
  `project.pbxproj` edit: the project uses `PBXFileSystemSynchronizedRootGroup`.
- `CheckStitch/AppGroup.entitlements` — App Group `group.app.alanvardy.CheckStitch`.
- `linear-project.md` — the Linear project to file tickets in (`CheckStitch`).
- `.pi/orksorksorks/<branch>/` — step artifacts; these are committed here.

## Build, run, gate

- `make build` — simulator build (`xcodebuild`, scheme `CheckStitch`).
- `make run` — build, then boot/install/launch on a simulator.
- `bash scripts/run-devices.sh` — install + launch on a real device
  (requires Developer Mode; prefers an iPhone). Honours `SCHEME`,
  `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` overrides.
- **There is no test target — the gate is `./scripts/test.sh`**, which runs
  the build plus `shellcheck` over `scripts/`. Do not add a test target as
  part of a small task; that is a ticket of its own.
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
