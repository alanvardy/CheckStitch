# Conventions

Shared factual appendix for Design/Structure/Plan. Repo:
/Users/vardy/dev/alanvardy-var-969-create-and-delete-checklists-from-a-scrollable-list

## Canonical commands

| Command | What it does |
|---|---|
| `make build` | `xcodebuild -scheme CheckStitch -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build` (Makefile `build` target) |
| `make run` | `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'`; APP=`DerivedData/Build/Products/Debug-iphonesimulator/CheckStitch.app` |
| `make clean` | `xcodebuild -scheme CheckStitch -destination '$(SIM)' clean` |
| `./scripts/test.sh` | **The gate.** `make build` + `shellcheck scripts/*.sh` (falls back to `bash -n` per script if shellcheck missing); prints `gate: ok` (scripts/test.sh:1-15) |
| `bash scripts/run-devices.sh` | Device build + install + launch via `devicectl` (requires Developer Mode; prefers an iPhone); honours SCHEME/BUNDLE_ID/CONFIGURATION/DERIVED_DATA overrides |

Makefile variables: `SCHEME := CheckStitch`, `CONFIGURATION := Debug`,
`DERIVED_DATA := DerivedData`, `BUNDLE_ID=app.alanvardy.CheckStitch`
(default in scripts).

## Simulator destination resolution (Makefile:4-6)

1. Explicit `SIM=` env/CLI override
2. Worktree `.simulator_id` → `platform=iOS Simulator,id=<UUID>`
3. Default `platform=iOS Simulator,name=iPhone 17`

- This worktree pins `.simulator_id` = `A5A9A41C-472B-4D6A-9262-9784ED28E8FE`.
- **Never** hardcode a bare `name=` destination in a script — it selects a
  shared device and wedges parallel agents (repo AGENTS.md).

## Test-suite inventory

- **There is no test target.** No CheckStitchTests, no unit tests, nothing
  platform-gated. The gate (`./scripts/test.sh`) is build + shellcheck of
  `scripts/`. Do not add a test target as part of a small task (repo AGENTS.md).
- Scripts are `#!/bin/bash` with `set -euo pipefail`, committed mode `100755`
  (`chmod +x` before committing). Keep the plural name `run-devices.sh` (the
  `r` fish alias runs it).
- The only runtime verification is the simulator: `xcrun simctl boot/bootstatus/
  install/launch` via run-simulator.sh, or devicectl on a Developer-Mode device.

## Signing / identity

- `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`
- App Group entitlement: `CheckStitch/AppGroup.entitlements` registers
  `group.app.alanvardy.CheckStitch` under `com.apple.security.application-groups`;
  wired as `CODE_SIGN_ENTITLEMENTS` for both configurations (q4 read of project.pbxproj).
- On a machine without the code-signing profile, add `-allowProvisioningUpdates`
  (scripts/run-devices.sh already does).
- `GENERATE_INFOPLIST_FILE = YES` (project.pbxproj:261, 303) ⇒
  `INFOPLIST_KEY_NSRemindersUsageDescription` and
  `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` are **already defined**
  in both configurations (project.pbxproj:262-263, 304-305). Do not regress them.
- `IPHONEOS_DEPLOYMENT_TARGET = 18.7`, `ONLY_ACTIVE_ARCH = YES` in Debug.
- New files under `CheckStitch/` need **no** project.pbxproj edit
  (`PBXFileSystemSynchronizedRootGroup`).

## Build/verify gotchas surfaced by research

- One simulator destination per worktree: `.simulator_id` must stay untouched by
  scripts; run-simulator.sh expects the full `platform=...` destination string.
- run-devices.sh needs `jq` and a device with `developerModeStatus == enabled`,
  non-null transportType and `tunnelState != unavailable`.
- No CI exists in the repo; nothing runs the gate off-commit.
- App Group Swift layer (reference pattern from /Users/vardy/dev/SingleThread):
  `AppGroup.suiteName` must match the registered group
  (SingleThreadCore/Sources/SingleThreadCore/AppGroup.swift:8-13); `AppGroup.defaults`
  = `UserDefaults(suiteName:) ?? .standard` (AppGroup.swift:15-19) so it falls
  back cleanly where groups are unavailable (watchOS sim, unregistered
  simulators, previews); the key/value API is `bool(forKey:)` / `integer(forKey:)`
  reads, `set(value, forKey:)` writes, `removeObject(forKey:)` deletes.
- Usage-description precedent: a stale/missing NSReminders*UsageDescription key
  surfaces as a real-install permission-text problem
  (SingleThread docs/SimulatorManualVerification.md:92).