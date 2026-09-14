# Conventions — CheckStitch

Shared factual appendix for Design / Structure / Plan. All refs are repo-relative.

## Build / run / verify commands

- **Build (simulator)**: `make build` — `xcodebuild -scheme CheckStitch`.
- **macOS compile leg (no signing, no provisioning)**: `make build-mac` — the gate's platform check.
- **Runnable signed macOS app**: `make build-mac-signed` — signs with the development team so `CheckStitch/AppGroup.entitlements` (incl. the KVS `com.apple.developer.ubiquity-kvstore-identifier`) is embedded; used by `run-devices.sh`; needs `-allowProvisioningUpdates` (already in target).
- **Run on simulator**: `make run` — build, then boot/install/launch, pinned to the resolved `.simulator_id` UDID (`open -a Simulator --args -CurrentDeviceUDID <udid>`).
- **Watch compile**: `make watch-build` (`Makefile:43-51`, `generic/platform=watchOS Simulator`; gate invokes at `scripts/test.sh:104-107`). Watch run: `bash scripts/run-watch.sh` (devicectl; never a bare name in a destination).
- **Device run**: `bash scripts/run-devices.sh` (Developer Mode; prefers an iPhone; honours `SCHEME`/`BUNDLE_ID`/`CONFIGURATION`/`DERIVED_DATA`).
- **Unit tests (fast)**: `make test-unit` (`Makefile:64-73`) — CheckStitchTests bundle on the macOS host: `-destination 'platform=macOS'`, `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests`. No sim boot, no App Group gap (`Makefile:62-63`).
- **UI smoke**: `make test-ui` (`Makefile:75-86`) — exactly one CheckStitchUITests case via `build-for-testing` → `test-without-building` on this worktree's `.simulator_id` simulator; `-only-testing:CheckStitchUITests`.
- **Full gate**: `./scripts/test.sh` — `make build` (simulator) → headless pre-boot of this worktree's simulator → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`, printing `gate: ok`. **Never declare work done while it fails.**
- **Shell helper tests**: `bash scripts/tests/run.sh` — not XCTest; stub-based regression tests for gate/simulator helpers (`mktemp -d` stubs prepended to `PATH` at `:23-38`, tally PASS/FAIL); gated by `GATE_TESTS_SKIP` in `scripts/test.sh:110`.

## Test-suite inventory

| Path | Style | Coverage | Platform |
|---|---|---|---|
| `CheckStitchTests/ChecklistCodecTests.swift` | XCTest (XCTestCase, `guard case .migratable(...) else XCTFail`) | envelope round-trip, v1-migratable, unknown-version→empty, unreadable vs unsupported, v1-without-sync-state | macOS host (unit bundle) |
| `CheckStitchTests/ChecklistStoreTests.swift` | XCTest | store load/migrate/save/rename/items/merge/apply; unique `"test.<UUID>"` `UserDefaults` per test (`:8-14`) | macOS host |
| `CheckStitchTests/ChecklistItemTests.swift` | Testing (`@Test(arguments:)`) | blank-title matrix; pure-value, no `@MainActor` | macOS host |
| `CheckStitchTests/ChecklistMergeTests.swift` | Testing | union/conflict/winner rules; member-level `@MainActor` on async helpers (`:160-175`) | macOS host |
| `CheckStitchTests/ChecklistWidthTests.swift` | Testing | UI width constants (header-only read) | macOS host |
| `CheckStitchTests/EventKitReminderCreatorTests.swift` | Testing | **construction canary only** — no EventKit API called; injected `sharedTestEventStore` | macOS host |
| `CheckStitchTests/ChecklistCreatorTests.swift` | Testing | creation outcomes via `SpyReminderCreator`; blank/trimmed titles via `@Test(arguments:)` | macOS host |
| `CheckStitchTests/ChecklistViewModelTests.swift` | Testing | `createChecklist` states via `makeViewModel(spy)` | macOS host |
| `CheckStitchTests/ChecklistSyncServiceTests.swift` | Testing | reconcile/seeded/push outcomes via `makeService(sync, store)` | macOS host |
| `CheckStitchTests/UbiquitousChecklistSyncTests.swift` | Testing | `realAdapterCanBeConstructed` canary only | macOS host |
| `CheckStitchTests/WatchChecklistStoreTests.swift` | Testing | `WatchChecklistStore` vs `FakeChecklistSyncTransport` | macOS host (watch sources compiled in unit bundle) |
| `CheckStitchTests/MacWindowFrameTests.swift` | — | whole-file `#if os(macOS)` (`:1`) | macOS only |
| `CheckStitchUITests/CheckStitchUITests.swift` | XCTest | one smoke: launch, `createChecklistButton`/`settingsButton` present, accessibility audit; `#if os(iOS)` on audit types (`:31-37`) | iOS Simulator (test-ui) |

- **Fixtures** live in `CheckStitchTests/TestFixtures.swift`: `makeItem` (`:6`), `makeIsolatedDefaults` (`:12-18`), `sharedTestEventStore` (`:22-23`), `SpyReminderCreator` (`:28-49`), `InMemoryChecklistSync` (`:52-80`), `TestError` (`:89-91`), `FakeChecklistSyncTransport` (`:96-127`), `SpyChecklistRunner` (`:129-132`).

## Gotchas and invariants

- **Actor isolation**: test targets do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` (`Makefile:63`); suites opt in per-suite/member with `@MainActor`. Never restore the app default on test targets; pure-value suites stay plain `struct`s.
- **`EKReminder` holds a weak ref to its `EKEventStore`**: a deallocated store SIGTRAPs on property read — hence the session-global `sharedTestEventStore` (`TestFixtures.swift:22-27`). Keep EventKit behavior tests on `SpyReminderCreator`; real-API tests must be construction canaries only.
- **Reminder creation API is deviceless on the seam**: `ReminderCreating` (`CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift:14-17`) exposes only `requestAccess() / create(title:)`; production path is `ChecklistReminders.create(from:)` (`CheckStitch/ChecklistReminders.swift:10-28`) which returns `Void` and treats permission-denied as a silent return. `save` is compiled out on watchOS via `#if !os(watchOS)`.
- **Destination pinning**: never a bare `name=` destination in a script — it selects a shared device and wedges parallel agents. Explicit `SIM=` > this worktree's `.simulator_id` > shared default (Makefile precedence doc).
- **Simulator windows**: the gate takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`), quits `Simulator.app` once, pre-boots this worktree's `.simulator_id` UDID headlessly between `make build` and `make test`, and shuts down only the resolved UDID on exit (`scripts/test.sh:27-30, 55-81`). Never `all`/`booted` shutdowns.
- **Codec/store invariants**: `ChecklistStore` is "the only encoder" (`CheckStitch/ChecklistStore.swift:85`) and shares key `"checklists.v1"` with the KVS sync layer (`CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift:23, 28-29`); a higher-`version` payload makes the store read-only (`canOverwriteStoredPayload = false`, `ChecklistStore.swift:70-72, 241-244`). Storage keys are never migrated.
- **Save coalescing**: text edits ride `scheduleSave()` (300 ms, `ChecklistStore.swift:45, 222-235`); structural edits call `save()` directly and cancel pending text saves (`:236-239`); `flushPendingSave()` runs on detail-screen `onDisappear` (`CheckStitch/ChecklistDetailView.swift:75`) and on `scenePhase != .active` (`CheckStitch/MyApp.swift:51-56, 77-82`).
- **Signed macOS + KVS**: the KVS entitlement (in `CheckStitch/AppGroup.entitlements`) is what lets `NSUbiquitousKeyValueStore` sync through iCloud on macOS; the unsigned `make build-mac` leg exists so the gate stays provisioning-free.
- **Scripts**: `scripts/*.sh` are `#!/bin/bash` with `set -euo pipefail`, committed `100755`. Unit tests import `@testable import CheckStitchCore`.