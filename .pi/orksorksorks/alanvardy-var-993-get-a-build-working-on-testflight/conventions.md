# Conventions — CheckStitch build/test/verify surface

Shared factual appendix for Design/Structure/Plan. Everything here is verified
as-is; no recommendations.

## Canonical commands

| Command | What it runs | Source |
|---|---|---|
| `make build` | `xcodebuild -scheme CheckStitch -destination '$(SIM)' -configuration Debug -derivedDataPath DerivedData build` — iOS Simulator unsigned build | Makefile:17-23 |
| `make build-mac` | macOS compile, `CODE_SIGNING_ALLOWED=NO build` — unsigned gate leg | Makefile:30-36 |
| `make build-mac-signed` | macOS signed app, `-allowProvisioningUpdates build` — runnable, embeds AppGroup.entitlements/KVS | Makefile:40-46 |
| `make run` | `build` then `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'` | Makefile:57-58 |
| `make watch-build` | `xcodebuild -scheme CheckStitchWatch -destination 'generic/platform=watchOS Simulator' build`, unsigned | Makefile:50-56 |
| `make test-unit` | `xcodebuild … -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` — fast pre-gate check | Makefile:64-71 |
| `make test-ui` | `build-for-testing` then `test-without-building -only-testing:CheckStitchUITests`, both on `$(SIM)` | Makefile:75-86 |
| `bash scripts/test.sh` | **The gate**: make build → sim lock/quit → pre-boot → make test → build-mac → watch-build → scripts/tests/run.sh → shellcheck → `gate: ok` | scripts/test.sh:33-121 |
| `bash scripts/tests/run.sh` | Shell-stub regression suite (17 cases), stubs xcrun/defaults/make/open/osascript on PATH | scripts/tests/run.sh:1-311 |
| `shellcheck scripts/*.sh scripts/tests/*.sh` | Static lint (fallback `bash -n` per file if shellcheck absent) | scripts/test.sh:114-118 |
| `make clean` | `xcodebuild -scheme CheckStitch -destination '$(SIM)' clean` | Makefile:88-89 |

- Device/wearable runs (not the gate): `bash scripts/run-devices.sh` (build `generic/platform=iOS` Debug + devicectl install/launch + macOS signed leg) and `bash scripts/run-watch.sh` (build `generic/platform=watchOS` + install/launch on the watch). Both need Developer Mode devices and `-allowProvisioningUpdates`.

## Test-suite inventory

| Suite | Files | Platform gating | What it covers |
|---|---|---|---|
| CheckStitchTests (unit) | `CheckStitchTests/` (Swift Testing: `struct <Thing>Tests`, `@Test`, `#expect`, `@MainActor` where touching EventKit/view model; fakes in `CheckStitchTests/TestFixtures.swift`) | macOS host (`-destination 'platform=macOS'`), no sim, no signing (`CODE_SIGNING_ALLOWED=NO`) | Models, EventKit seam, checklist creator, view model (VAR-969 store/codec XCTest suites also live here) |
| CheckStitchUITests (UI smoke) | `CheckStitchUITests/` — exactly one XCTest case | Worktree's own simulator (`$(SIM)`), via `build-for-testing` → `test-without-building` | One UI smoke |
| scripts/tests/run.sh (shell) | `scripts/tests/` | Host bash; stubs on PATH; no real tools | resolve-sim-udid, gate boot/shutdown/lock behavior, run-simulator, run-watch (watch bundle id `app.alanvardy.CheckStitch.watchkitapp`), macOS sandbox egress pin, pbxproj sandbox check |
| CheckStitchWatch | — (no test target; compile-only via `make watch-build` / run-watch.sh) | watchOS Simulator SDK | Compile of the shared package for watchOS |

- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with `@MainActor`. Never restore the app's default there (Makefile:63 comment).

## Signing / identity facts (must survive any change)

- Team `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, `CODE_SIGN_STYLE = Automatic` — pbxproj:490-496 (Debug), :535-541 (Release).
- Bundle ids: `app.alanvardy.CheckStitch` (pbxproj:517/:562), tests `…Tests` (:588/:613), UI tests `…UITests` (:637/:661), watch `app.alanvardy.CheckStitch.watchkitapp` (:689/:718). Watch embeds `INFOPLIST_KEY_WKCompanionAppBundleIdentifier = app.alanvardy.CheckStitch` (:685/:714).
- App Group `group.app.alanvardy.CheckStitch` + KVS key `$(TeamIdentifierPrefix)app.alanvardy.CheckStitch` — only in `CheckStitch/AppGroup.entitlements` (`CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*|iphonesimulator*|macosx*]`, pbxproj:491-493/:536-538).
- `GENERATE_INFOPLIST_FILE = YES` on all targets — Reminders usage text is `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` / `INFOPLIST_KEY_NSRemindersUsageDescription` (pbxproj:502-503/:547-548). No physical Info.plist.

## Build/verify gotchas

- **Destination pinning**: never leave a bare `name=` destination in a script — it selects a shared device. Precedence: explicit `SIM=` env > worktree `.simulator_id` (`platform=iOS Simulator,id=<udid>`) > shared fallback (Makefile:4-5). The gate enforces with `resolve-sim-udid.sh --require-id` (test.sh:24); a present-but-unresolvable `.simulator_id` is a hard error (test.sh:25-27).
- **Simulator windows**: gate quits Simulator.app once (test.sh:88) and pre-boots only the resolved UDID; never `shutdown all/booted`; single EXIT trap (test.sh:87, :79-85). Bounded lock `${TMPDIR:-/tmp}/checkstitch-simulator.lock` (test.sh:40-41, `LOCK_TIMEOUT` default 60) serializes concurrent gates across worktrees; stale locks (dead PID) reaped (test.sh:49-54).
- **Gate env hooks for tests**: `GATE_TESTS_SKIP=1` suppresses scripts/tests/run.sh (test.sh:111); `SIM`, `SIM_ID_FILE`, `TMPDIR`, `LOCK_TIMEOUT` all honored (test.sh:7, 13, 40-41).
- **Sandbox egress pin**: every `ENABLE_APP_SANDBOX = YES` buildSettings block must also set `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` (pbxproj:497-498 et al; enforced by scripts/tests/run.sh:282-308).
- **No provisioning profile specifiers in pbxproj**: signed legs rely on `-allowProvisioningUpdates` (Makefile:44, scripts/run-devices.sh:125, scripts/run-watch.sh:87) to fetch profiles for team `6NWX2DHB9Q`. The gate's machinery stays provisioning-free.
- **Signed macOS leg** (`build-mac-signed`) is the only runnable macOS app; the unsigned `build-mac` is the gate's platform check. On a machine without the profile, add `-allowProvisioningUpdates` (already in the target).
- **One-process-at-a-time**: gate holds the simulator; `make test-ui` runs the single UI smoke on the worktree simulator; `make build`/`test-unit` need no simulator boot.
- **Scripts hygiene**: `scripts/*.sh` are `#!/bin/bash` with `set -euo pipefail`, committed mode 100755; pytest-style shell cases in scripts/tests/run.sh assert them.
- **Parallel worktree risk**: only this worktree's `.simulator_id` (currently `9015DDB2-CE77-4FEA-A172-E461B25D6D0A`) is used by its gate; `run-devices.sh`/`run-watch.sh` require real devices with Developer Mode.
- **Reference app**: `/Users/vardy/dev/SingleThread` is the in-house reference for Reminders/EventKit (`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`), for the macOS App Store Connect distribution path (`scripts/distribute-macos.sh` + `exportOptions.plist` with `method = app-store-connect`, team `6NWX2DHB9Q`), and for GitHub Actions CI that neutralizes signing via `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV` (.github/workflows/ci.yml). CheckStitch has **no** `.github/` and **no** distribution targets of any kind.
