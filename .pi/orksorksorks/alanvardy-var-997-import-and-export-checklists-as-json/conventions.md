# Conventions

Dense reference for Design/Structure/Plan — canonical commands, test-suite inventory, and build/verify gotchas. Project-level rules are documented in `AGENTS.md`; this appendix pins the file:line facts.

## Canonical commands

- `make build` — simulator build (`xcodebuild`, scheme `CheckStitch`).
- `make build-mac` — unsigned macOS compile leg (the gate's platform check; no signing, no provisioning).
- `make build-mac-signed` — runnable signed macOS app (dev team `6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, `CheckStitch/AppGroup.entitlements` incl. KVS `com.apple.developer.ubiquity-kvstore-identifier`); needs `-allowProvisioningUpdates`.
- `make run` — build then boot/install/launch on a simulator (window pinned to resolved UDID).
- `make watch-build` — watchOS simulator compile of `CheckStitchWatch` (same `CheckStitchCore` package, watchOS SDK), unsigned, sim-free.
- `bash scripts/run-watch.sh` — build `CheckStitchWatch`, install + launch on the paired Apple Watch via `devicectl` (watch resolved by name to an id — never a bare name in a destination).
- `bash scripts/run-devices.sh` — install + launch on a real device (Developer Mode; prefers iPhone). Honours `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` overrides.
- **The gate is `bash scripts/test.sh`** — `make build` (simulator) → headless pre-boot of this worktree's `.simulator_id` → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`; prints `gate: ok`. `scripts/tests/run.sh` is also runnable alone (stubs `xcrun`/`defaults`/`make`/`open`/`osascript` on PATH).
- `make test` = `make test-unit` + `make test-ui` (`Makefile:60`).
  - `make test-unit` (`Makefile:64-70`) — `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests`; no sim, no signing. Fast loop: run before the full gate.
  - `make test-ui` (`Makefile:75-80`) — exactly one `CheckStitchUITests` smoke case via `build-for-testing` → `test-without-building` on this worktree's `.simulator_id`.

## Test-suite inventory (all under `CheckStitchTests/` unless noted)

| Suite | Framework | Platform gating | Covers |
|---|---|---|---|
| `ChecklistCodecTests.swift` | XCTest, `@MainActor` (:1,5,6) | none | codec round trips, v1/v2/v3 migratable, unsupported vs unreadable, malformed → unreadable |
| `ChecklistStoreTests.swift` | XCTest, `@MainActor` (:1,5,6) | none | persistence, sameName, tombstones (:779, :800), apply/remote merge (:824, :837-894), canOverwriteStoredPayload (:137), onChange |
| `ChecklistSyncServiceTests.swift` | Swift Testing, `@MainActor` (:3,7,28) | none | seeding, migration, merge+push single-write, failure paths, coalescing, observer → reconcile; uses `pushDelay: nil` |
| `ChecklistMergeTests.swift` | Swift Testing | — | merge engine (tombstone-keyed union, LWW) |
| `ChecklistSyncMessageTests.swift` | Swift Testing | — | codec message integrity (watch transport) |
| `ChecklistSyncCoordinatorTests.swift` | Swift Testing | — | iOS phone-sync coordinator |
| `UbiquitousChecklistSyncTests.swift` | Swift Testing (:5) | — | construction canary; `startObserving` cancel idempotence |
| `WatchChecklistStoreTests.swift` | Swift Testing (:6) | watchOS (imports `CheckStitchCore`) | watch-side store |
| `ChecklistRemindersTests.swift` | Swift Testing (:7) | — | reminders creation |
| `ViewRenderTests.swift`, `CardPlateTests.swift`, `AboutViewTests.swift`, `MacWindowFrameTests.swift` | Swift Testing | `MacWindowFrameTests.swift:1` whole-file `#if os(macOS)`; inline `#if os(macOS)` at `ViewRenderTests.swift:27`, `ChecklistDetailViewTests.swift:60`, `AboutViewTests.swift:23` | view rendering / frames |
| `ChecklistDetailViewTests.swift` | Swift Testing | inline `#if os(macOS)` | detail view interactions |
| `TestFixtures.swift` | fakes | — | `InMemoryChecklistSync` (:89-117), fake observation (:96-132), injectable store (:22-56) |

`CheckStitchUITests/CheckStitchUITests.swift` — XCTest XCUITest (:1,2,14): one smoke case (launch, wait for create/settings/empty-state buttons), `#if os(iOS)` limited accessibility audit else full (:33-39); `runsForEachTargetApplicationUIConfiguration = false` (:13), `continueAfterFailure = false` (:14).

Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` (`Makefile:63`); suites opt in with `@MainActor` — never restore the app default in the test targets.

## Build / verify gotchas

- **Destination precedence** (`Makefile`): explicit `SIM=` > this worktree's `.simulator_id` > shared default. Never leave a bare `name=` destination in scripts — it selects a shared device and wedges parallel agents. A missing `.simulator_id` skips the pre-boot; a present-but-unresolvable one is a hard gate error.
- **Simulator windows**: a running `Simulator.app` attaches a window to every device booted while alive. No headless flag exists. The gate takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`, `LOCK_TIMEOUT` default 60s; stale-lock PID reaped), quits `Simulator.app` once, pre-boots the worktree UDID headlessly between `make build` and `make test`, shuts down that UDID in an EXIT trap — never `all`/`booted`. The `com.apple.iphonesimulator AutoOpenDevice` pref is ineffective on this toolchain (proven spike) — do not reintroduce it.
- **Signing**: dev team `6NWX2DHB9Q`, App Group `group.app.alanvardy.CheckStitch`; without the profile add `-allowProvisioningUpdates`. macOS slice signs with the same team + entitlements (KVS entitlement is what lets `NSUbiquitousKeyValueStore` sync via iCloud on macOS). Unsigned `make build-mac` exists only so the gate stays provisioning-free.
- **`GENERATE_INFOPLIST_FILE = YES`** — any new Reminders/EventKit strings must land in `NSReminders*UsageDescription` keys (see reference impl `/Users/vardy/dev/SingleThread` — `EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`).
- **New files under `CheckStitch/` need no `project.pbxproj` edit** — `PBXFileSystemSynchronizedRootGroup` picks them up.
- **Scripts**: `#!/bin/bash` + `set -euo pipefail`, mode `100755`. Keep the `run-devices.sh` plural name (the `r` fish alias runs it).
- **`hx` panics without a TTY** — always `git commit -m "..."`; interactive rebase steps need `git -c core.editor=true rebase --continue`. Leftover `.git/index.lock` after a crashed git is stale — `rm` it.
- **Shell-test gate**: `bash scripts/tests/run.sh` stubs dev tools on PATH so `shellcheck`-checked scripts are exercised without a toolchain.
- **Latest worktree facts**: repo root `/Users/vardy/dev/CheckStitch` (worktrees per ticket, `git worktree`); current branch `alanvardy-var-997-import-and-export-checklists-as-json`. Artifacts live in `.pi/orksorksorks/<branch>/` and are committed.