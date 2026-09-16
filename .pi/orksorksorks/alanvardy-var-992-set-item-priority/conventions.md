# Conventions and Gate Reference

Shared factual appendix for Structure and Plan phases. Dense references; no
re-reading of the Makefile / scripts / test-suite set required.

## Canonical commands

- **Gate**: `bash scripts/test.sh` — order: `make build` → resolve/pre-boot the
  worktree's pinned simulator → `make test` → `make build-mac` → `make
  watch-build` → `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh
  scripts/tests/*.sh` → prints `gate: ok` (AGENTS.md; pipeline detail from
  research). `GATE_TESTS_SKIP=1` skips the shell-test leg.
- **Fast verify**: `make test-unit` first (`AGENTS.md`); full gate only after.
- **Makefile targets** (`Makefile:33-89`):
  - `make build` — iOS Simulator xcodebuild, scheme `CheckStitch`, `-configuration
    Debug -derivedDataPath DerivedData` (`Makefile:35-39`).
  - `make build-mac` — macOS compile leg, `CODE_SIGNING_ALLOWED=NO` (`:41-47`).
  - `make build-mac-signed` — runnable macOS app, `-allowProvisioningUpdates`
    (`:51-57`); needs the dev-team provisioning profile.
  - `make watch-build` — watchOS Simulator, scheme `CheckStitchWatch` (`:61-66`).
  - `make test` == `test-unit` + `test-ui` (`:61`).
  - `make run` — build then `scripts/run-simulator.sh` window request.
- **`make test-unit`** (`Makefile:66-70`): `-destination 'platform=macOS'`,
  `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests`. Test targets do
  **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` (`Makefile:59` comment) — suites
  opt in per suite with `@MainActor`; never restore the app default on test
  targets.
- **`make test-ui`** (`Makefile:74-82`): `build-for-testing` → `test-without-
  building -only-testing:CheckStitchUITests` on the pinned SIM.
- **Destination precedence** (`Makefile:5-9`): explicit `SIM=` > this worktree's
  `.simulator_id` (`platform=iOS Simulator,id=<UDID>`) > shared default
  `name=iPhone 17`. Never leave a bare `name=` destination in a script.
- **Simulator pre-boot / lock** (`scripts/test.sh:35-82`): host lock file
  `${TMPDIR:-/tmp}/checkstitch-simulator.lock`, `LOCK_TIMEOUT=60`, stale-lock
  reap by dead holder PID (`:41-48`), warn-and-continue past timeout (`:49-52`);
  one EXIT trap releases the lock and shuts down **only the resolved gate UDID**
  — never `all`/`booted` (`:62-77`); `osascript` quits Simulator.app so no
  window attaches (`:58-59`). Missing `.simulator_id` → skip pre-boot; present
  but unresolvable → hard error.
- **Shell tests**: `bash scripts/tests/run.sh` — stubs `xcrun`/`defaults`/
  `make`/`open`/`osascript`; covers `resolve-sim-udid.sh` (id/name forms,
  `--require-id`, non-UUID errors), gate behaviors, `run-simulator.sh` window
  request, `run-watch.sh`, and a pbxproj awk pin (every `ENABLE_APP_SANDBOX`
  block also sets `ENABLE_OUTGOING_NETWORK_CONNECTIONS`).
- **shellcheck** (`scripts/test.sh:124-128`): on all `scripts/*.sh`
  `scripts/tests/*.sh`; falls back to `bash -n` with a warning if missing.
- `scripts/*.sh` are `#!/bin/bash` + `set -euo pipefail`, committed mode 100755.

## Test-suite inventory (`CheckStitchTests/`, 36 files incl. fixtures)

- **Swift Testing** (`import Testing` / `struct <Thing>Tests`, behaviour-named
  funcs, `@Test`, `@Test(arguments:)`, `#expect`) for nearly everything.
  MacOS-hosted (`-destination platform=macOS`).
- **XCTest (3 files, all `@MainActor`)**:
  - `ChecklistCodecTests.swift:1` — version classify/migration, additive-field
    absent-key, encoder-writes-every-key, field-clock round trip, regression
    `:253`.
  - `ChecklistStoreTests.swift:1` — store load/save, corrupt-payload repair,
    unsupported-version no-overwrite, `apply` idempotence/no-push/newer-refusal
    (`:992-1126` region).
  - `ChecklistExportTests.swift:1` — exported bytes classify `.loaded`.
- **Model/codec**: `ChecklistItemTests.swift` (`:26,:31,:42,:50,:59,:88`),
  `ChecklistItemDateTests.swift`.
- **Store/view-model**: `ChecklistStoreTests.swift`, `ChecklistViewModelTests.swift`,
  `SettingsDataActionQueueTests.swift`.
- **Sync/merge**: `ChecklistMergeTests.swift` (field-clock merge `:139-155`,
  coarse-vs-field skew `:334-364`, tombstone-vs-field `:289-295`, order
  `:449-563`, replay no-op `:638-639`), `ChecklistSyncServiceTests.swift`
  (cloud v1/v2 back-compat `:65,:90`, payload seeding `:163,:207`),
  `ChecklistSyncCoordinatorTests.swift`, `ChecklistSyncMessageTests.swift`,
  `UbiquitousChecklistSyncTests.swift`, `ChecklistImportSessionTests.swift`
  (`:57,:70,:79`).
- **View tests** (mostly `String(describing:)` assertions):
  `ChecklistDetailViewTests.swift` (incl. `itemEditViewBuffersItsDateText` `:152`,
  renders for existing item `:192`, not-found `:212`), `ViewRenderTests.swift`,
  `AboutViewTests.swift`, `ExportChecklistsViewTests.swift`,
  `BackgroundPhotoLayerTests.swift`, `MacWindowFrameTests.swift` (whole-file
  `#if os(macOS)`).
- **Platform gating `#if os(...)`**: `MacWindowFrameTests.swift:1` whole-file;
  function blocks at `ViewRenderTests.swift:27`, `ExportChecklistViewTests.swift:
  35`, `ChecklistDetailViewTests.swift:72,164,202,218`, `AboutViewTests.swift:23`.
- **`@Suite(.serialized)`** (only these two — shared `UserDefaults.standard`):
  `BackgroundImageStoreTests.swift:8`, `SettingsBindingsTests.swift:6`.
- **`@MainActor`**: nearly every suite + fixtures
  (`TestFixtures.swift:22,27,56,88,119,132,165`); per-function at
  `ChecklistSyncServiceTests.swift:340,347,353`, `ChecklistMergeTests.swift:
  672,677,686,699`. Suites touching EventKit or the view model are `@MainActor`.
- **UI smoke**: `CheckStitchUITests/CheckStitchUITests.swift` — XCTest,
  `@MainActor` (`:12`), exactly one case `testLaunchAndAccessibilitySmoke`
  (`:13`, `#if os(iOS)` guard `:34`).
- **Fixtures**: fakes live in `CheckStitchTests/TestFixtures.swift`.
  Legacy payloads are inline `Data(#"..."#.utf8)` literals inside test bodies —
  **no fixture files** anywhere in the repo.

## Build/verify gotchas surfaced by research

- One simulator-touching test process at a time: bounded host lock; never run
  two gates on the same host concurrently without `LOCK_TIMEOUT` awareness.
- `test-unit`/`build-mac` need `CODE_SIGNING_ALLOWED=NO`; `test-ui` and `make
  run` need a resolved UDID destination (worktree `.simulator_id`).
- Signing: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`,
  App Group `group.app.alanvardy.CheckStitch`; without the provisioning profile
  add `-allowProvisioningUpdates` (already in `build-mac-signed`). Do not
  re-derive the team from `~/Library/Developer/Xcode`.
- New files under `CheckStitch/` need no `project.pbxproj` edit
  (`PBXFileSystemSynchronizedRootGroup`); `CheckStitchCore` is a local
  sources-only SPM package imported by the app, watch, and test targets.
- Reference implementation for Reminders/EventKit work:
  `/Users/vardy/dev/SingleThread` (`EKReminder` +
  `defaultCalendarForNewReminders()` + `save(commit: true)`; `NSReminders*`
  usage-description keys required — `GENERATE_INFOPLIST_FILE = YES`).
- SwiftUI API questions: the compiler is the oracle — edit, then
  `make build` / `make test-unit` (never mine SDK symbol graphs).
- Sync/icon/render tickets cannot close on static evidence — verify the
  installed bundle on the target device and state what the user should see.