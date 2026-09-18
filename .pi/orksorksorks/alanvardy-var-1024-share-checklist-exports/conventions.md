# Conventions — CheckStitch (shared appendix for Design / Structure / Plan)

Dense, factual appendix so later phases need not re-open the Makefile, scripts,
or test suites. Paths relative to the repo root unless absolute. All refs
approximate line numbers from research.

## Build / run / test commands

- **The gate is `./scripts/test.sh`** → prints `gate: ok` (AGENTS.md). Legs:
  `make build` (simulator) → headless pre-boot of this worktree's
  `.simulator_id` UDID → `make test` → `make build-mac` → `make watch-build`
  → `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`.
- `make build` — simulator build, scheme `CheckStitch`.
- `make build-mac` — unsigned macOS compile leg (the gate's platform check).
- `make build-mac-signed` — runnable macOS app, signed w/ dev team so
  `CheckStitch/AppGroup.entitlements` (incl. KVS identifier) is embedded;
  needs `-allowProvisioningUpdates` (already in target). Outside gate warnings
  enforcement.
- `make run` — build + boot/install/launch on a simulator.
- `make watch-build` — watchOS simulator compile of `CheckStitchWatch`.
- `make test-unit` — `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`
  (no sim, no signing). Fast loop; run before the full gate.
- `make test-ui` — the one `CheckStitchUITests` smoke via
  `build-for-testing` → `test-without-building` on this worktree's `.simulator_id`.
- `bash scripts/run-devices.sh` — install + launch on real device (+ host Mac,
  + paired Apple Watch via `run-watch.sh` leg unless `RUN_WATCH=0`). Honours
  `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA`.
- `bash scripts/run-watch.sh` — build `CheckStitchWatch`, install + launch on
  the paired watch via `devicectl` (resolve watch name to an id, never a bare name).
- `make test` (Full test) presumably wraps test-unit + test-ui per target.

## Warnings-as-errors

- Every compiling gate leg passes `WARNINGS_AS_ERRORS`
  (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES`), so
  a compiler warning fails the gate. `scripts/tests/run.sh`
  (`warnings_as_errors_reaches_compiling_legs`) pins the flag per leg.
  `build-mac-signed`, `run-watch.sh`, `run-devices.sh` are outside enforcement.

## Simulator lock protocol

- The gate takes a bounded host lock
  (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`), quits `Simulator.app` once,
  pre-boots this worktree's `.simulator_id` UDID headlessly between `make build`
  and `make test`, releases the lock after `make test`. Single EXIT trap also
  releases the lock and shuts down that UDID. Stale lock (dead recorded PID)
  reaped. Missing `.simulator_id` → skip; present-but-unresolvable → hard error.
  Shutdown scoped to resolved UDID only (never `all`/`booted`). `LOCK_TIMEOUT`
  (default 60) bounds the wait. Non-gate build/test of a simulator target can
  hit a hot `DerivedData` — see gotcha below.

## Test-suite inventory + platform gating

- **CheckStitchTests/** (Swift Testing, macOS-hosted) + extra XCTest suites
  (VAR-969 store/codec). `@testable import CheckStitchCore` / `@testable import
  CheckStitch`. Run on `platform=macOS`. Import export-related suites:
  - `ChecklistExportTests.swift` (XCTest, `@MainActor`) — codec round-trip,
    `fileWrapper` bytes, filename stability. *Semantic* data equality, not
    byte-for-byte (independent `JSONEncoder` encodes aren't byte-identical).
  - `ChecklistImportExportViewModelTests.swift` (Swift Testing, `@MainActor`) —
    `isExporting`/`exportDocument`/`isShowingExport` after `exportSelected()`,
    empty-selection → no export, import error strings, FIFO conflict queue.
  - `ExportChecklistsViewTests.swift` (Swift Testing, `@MainActor`) —
    `canExport`/`toggled`; `renders` helper is the **only** platform-gated
    assertion in the export tests (`#if os(macOS)` → `nsImage != nil`, else
    `uiImage != nil`).
  - Other suites pin adjacent surface: `SettingsDataActionQueueTests`
    (`.stage`/`.take`), `UbiquitousChecklistSyncTests` (KVS), `WatchChecklistStoreTests`.
- **CheckStitchUITests/CheckStitchUITests.swift** (one XCTest smoke) — launches
  app, asserts `createChecklistButton`/`settingsButton`, handles empty-vs-list,
  accessibility audit guarded `#if os(iOS)`. **No export coverage.**
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites
  opt in with `@MainActor`. Do not restore the app default there.

## Build / verify gotchas

- **Concurrent builds wedge DerivedData.** Two builds on the same worktree can
  fail `make build` with `build.db: database is locked … two concurrent builds
  running` — environmental, not a code error. Run the gate/build when no other
  CheckStitch build holds `DerivedData` (observed during research).
- **Never leave a bare `name=` destination** in a script — selects a shared
  device and wedges parallel agents. Destination precedence: explicit `SIM=` >
  this worktree's `.simulator_id` > shared default (Makefile).
- **`hx` panics without a TTY** — always `git commit -m "..."`; interactive
  rebase steps via `git -c core.editor=true rebase --continue`.
- **Scripts** are `#!/bin/bash` with `set -euo pipefail`, committed mode 100755
  (`chmod +x`). Keep the plural `run-devices.sh`.
- **Info.plist** is fully generated (`GENERATE_INFOPLIST_FILE = YES` on all
  targets, project.pbxproj:501/546/584/609/633/657/683/712). Remaining keys are
  `INFOPLIST_KEY_*` (incl. `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription`/
  `INFOPLIST_KEY_NSRemindersUsageDescription` = "CheckStitch needs access to
  create reminders." at pbxproj:502-503/547-548) plus localized
  `InfoPlist.strings` per `.lproj/`. Q4 flagged Info.plist escape hatches
  (`LSSupportsOpeningDocumentsInPlace`/`UIFileSharingEnabled`) for the share
  "Save to Files" bug — these would be new `INFOPLIST_KEY_*`/string entries if
  adopted, and must survive on both iOS and macOS slices.
- **App target** is one source set compiled for iOS **and** macOS
  (`SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx"`, SDKROOT auto,
  pbxproj:522/567); platform code is gated with `#if os(...)` inside shared go
  files. Watch target is separate (`SDKROOT = watchos`). New files under
  `CheckStitch/` need **no** pbxproj edit (`PBXFileSystemSynchronizedRootGroup`).

## Signing

- `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App
  Group `group.app.alanvardy.CheckStitch`. macOS slice signs with same team
  (`CODE_SIGN_IDENTITY[sdk=macosx*] = "Apple Development"`,
  `CODE_SIGN_ENTITLEMENTS[sdk=macosx*] = CheckStitch/AppGroup.entitlements`).
  Do not re-derive the team from `~/Library/Developer/Xcode`.

## SwiftUI / SDK ground-truth rules

- The compiler is the oracle — to verify an API exists or a chain compiles,
  `make build` / `make test-unit`, never mine `.swiftinterface` files (swiftui-sdk
  skill). Sync/icon/render tickets cannot close on static evidence — verify on
  the installed bundle and state what the user should see (devicectl).
- Reference implementation for Reminders/EventKit: `/Users/vardy/dev/SingleThread`
  (an `EKReminder` + `defaultCalendarForNewReminders()` + `try
  eventStore.save(reminder, commit: true)` pattern; `NSReminders*UsageDescription`
  keys required because `GENERATE_INFOPLIST_FILE = YES`).