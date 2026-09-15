# Conventions — shared factual appendix for Design, Structure, Plan

## Canonical commands

- **Gate (full)**: `./scripts/test.sh` — `make build` (simulator) →
  headless pre-boot of this worktree's `.simulator_id` simulator → `make
  test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh`
  → `shellcheck scripts/*.sh scripts/tests/*.sh`; prints `gate: ok`
  (`scripts/test.sh:121`).
- **Fast unit verify**: `make test-unit` — builds `CheckStitchTests` on
  `platform=macOS` with `CODE_SIGNING_ALLOWED=NO` (Makefile `:64-69`);
  no simulator, no signing.
- **UI smoke**: `make test-ui` — exactly one `CheckStitchUITests` case via
  `build-for-testing` (`:80`) → `test-without-building` (`:86`); needs this
  worktree's simulator.
- **Builds**: `make build` (simulator, `:17`), `make build-mac` (`:30-35`,
  unsigned, `CODE_SIGNING_ALLOWED=NO`), `make build-mac-signed` (`:40`),
  `make watch-build` (`:50`).
- **Real device**: `bash scripts/run-devices.sh` (requires Developer Mode).
- **Unit test invocation form**: Swift Testing structs with `@Test`
  functions (behaviour-named, never `test`-prefixed); XCTest only for the
  VAR-969 store/codec suites.

## Test-suite inventory

All under `CheckStitchTests/`, macOS-hosted (Swift Testing or XCTest). Test
targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`, so every
suite opts in with `@MainActor` (AGENTS.md; Makefile `:63` comment).

| Suite | File | Kind | Coverage |
|---|---|---|---|
| `ChecklistMergeTests` | `ChecklistMergeTests.swift:7` | Swift Testing struct | merge: LWW wins `:26 :45 :118 :139`, no-clobber union `:96 :152`, tombstones `:65`, idempotence `:164`, order LWW `:185 :214 :335`; fixtures bottom of file; fixed date literals |
| `ChecklistCodecTests` | `ChecklistCodecTests.swift:6` | XCTest (VAR-969) | round-trips `:7 :103`, v1/v2/v3 migrate-classification `:29 :98 :168`, unknown/future version `:43 :98`, unreadable-vs-unsupported `:193`; raw JSON literals, byte-level asserts |
| `ChecklistStoreTests` | `ChecklistStoreTests.swift:6` | XCTest (VAR-969) | store CRUD/persistence, unique `UserDefaults` per test `:10-15`, injectable `Clock` `:39`, stamping `:394 :419`, migration `:310 :365`, guards `:137`, debounce `:152`, `apply(remote:)` block `:750-931` (`MARK` at `:931`), duplicate `:465 :581` + section `:933+` |
| `ChecklistSyncServiceTests` | `ChecklistSyncServiceTests.swift:7` | Swift Testing struct | seed `:29`, v1/v2 absorb `:65`, push-back idempotence `:149`, description survives merge+push `:129`, unreadable ignored `:220`, observer `:240`; `InMemoryChecklistSync` fake, `pushDelay: nil` |
| `ChecklistSyncCoordinatorTests` | `ChecklistSyncCoordinatorTests.swift:6` | Swift Testing struct | start/run/activation push; `FakeChecklistSyncTransport`/`SpyChecklistRunner`; asserts decoded contexts |
| `WatchChecklistStoreTests` | `WatchChecklistStoreTests.swift:6` | Swift Testing struct | context replace, v2 compat, run-once, rejected-run, destination/description survive |
| `UbiquitousChecklistSyncTests` | `UbiquitousChecklistSyncTests.swift:5` | Swift Testing struct | construction canary + cancel idempotence — never touches KVS APIs on the test host |
| `ChecklistUITests/` | XCTest smoke | `#if os(macOS)`-gated view tests (e.g. `ChecklistDetailViewTests`) |

Fakes (`InMemoryChecklistSync`, `FakeChecklistSyncTransport`,
`SpyChecklistRunner`, `TestError`) live in `CheckStitchTests/TestFixtures.swift`. Time is injected everywhere: store
`Clock` (`ChecklistStoreTests.swift:39`), fixed epoch-date literals in
merge/codec/service fixtures, one `Task.sleep` for the observer test
(`ChecklistSyncServiceTests.swift:240` region). No suite yields to a live
clock.

## Build/verify gotchas

- **Simulator windows**: a running `Simulator.app` attaches a window to every
  device booted while alive; there is no headless flag on this toolchain.
  The gate serializes via a bounded host lock
  (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`, `scripts/test.sh:40-99`),
  pre-boots only this worktree's `.simulator_id` UDID, and shuts down only
  that UDID — never `all`/`booted`. Missing `.simulator_id` → skip pre-boot;
  present-but-unresolvable → hard error (`scripts/test.sh:26-27`).
  `LOCK_TIMEOUT` (default 60) degrades to a warning.
- **One test process at a time**: `make test-ui` runs exactly one
  `CheckStitchUITests` smoke case; UI smoke stays XCTest. Simulator-touching
  steps in the gate must not run concurrently across worktrees (the lock
  exists for this).
- **Destination pinning**: scripts must never use a bare `name=` simulator
  destination (selects a shared device and wedges parallel agents); use the
  resolved UDID (`.simulator_id`) or the Makefile's default resolution.
- **Signing**: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle
  `app.alanvardy.CheckStitch`, `-allowProvisioningUpdates` needed only
  without the team profile. `make build-mac` is the unsigned, gate-only leg.
- **Shell scripts**: `scripts/*.sh` are `#!/bin/bash` with `set -euo
  pipefail`, committed `100755`; linted by `shellcheck` in the gate.
- **Codec discipline**: `classify` maps `loaded` vs `migratable` vs
  `unsupportedVersion`/`unreadable` (`Checklist.swift:310`); additive
  optional keys ship without a version bump (`description` precedent,
  `Checklist.swift:53-54`); wrong-typed keys make a payload `.unreadable`.
- **Store is the only encoder** of the envelope (`envelope` property,
  `ChecklistStore.swift:105`, doc `:103-104`); `save()` refuses while
  `canOverwriteStoredPayload` is false (`:370`).
- **Unit-vs-XCTest rule**: Swift Testing structs + `@MainActor` for new
  unit suites; XCTest reserved for the store/codec suites and the UI smoke.
  Run `make test-unit` before the full gate.