# Conventions — shared factual appendix

Verified against `Makefile`, `scripts/`, `project.pbxproj`, and the repo
`AGENTS.md` (source of truth for workflow rules). Researchers' file:line
references for code files are in `research.md`.

## Build, test, gate commands

- **The gate is `bash scripts/test.sh`** (prints `gate: ok`). Sequence: `make build` (simulator) → headless pre-boot of this worktree's `.simulator_id` simulator → `make test` → `make build-mac` (unsigned macOS compile leg, `CODE_SIGNING_ALLOWED=NO`) → `make watch-build` → `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`.
- `make build` — simulator build (`xcodebuild`, scheme `CheckStitch`).
- `make test` → `test-unit` + `test-ui`.
- `make test-unit` — `CheckStitchTests` on `platform=macOS`, `-only-testing:CheckStitchTests`, `CODE_SIGNING_ALLOWED=NO`; no sim, no signing. Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` — suites opt in with `@MainActor`.
- `make test-ui` — exactly one `CheckStitchUITests` smoke (`build-for-testing` → `test-without-building` `-only-testing:CheckStitchUITests`) on this worktree's `.simulator_id` simulator.
- `make build-mac-signed` — runnable macOS app, signed with development team (needs `-allowProvisioningUpdates`, already in target); used by `scripts/run-devices.sh`.
- `make watch-build` — watchOS simulator compile of `CheckStitchWatch` (same `CheckStitchCore` package), unsigned, sim-free. `bash scripts/run-watch.sh` installs/launches on the paired watch via `devicectl` (resolved by name → identifier, never a bare name destination).
- `bash scripts/run-devices.sh` — install + launch on a real device; honours `SCHEME`/`BUNDLE_ID`/`CONFIGURATION`/`DERIVED_DATA` overrides.
- Fast inner loop: `make test-unit` before the full gate. `make clean` exists.

## Simulator discipline

- Destination precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared default. Never a bare `name=` destination in a script.
- The gate takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`, `LOCK_TIMEOUT` default 60), quits `Simulator.app` once before the simulator leg, pre-boots the `.simulator_id` UDID headlessly, releases the lock after `make test`; single EXIT trap releases lock + shuts down that UDID (scoped to the resolved UDID only). Stale locks (dead recorded PID) are reaped. Missing `.simulator_id` → skip; present-but-unresolvable → hard error.
- `make run` requests its window explicitly pinned to the resolved UDID (`open -a Simulator --args -CurrentDeviceUDID <udid>`).
- Shell tests: `bash scripts/tests/run.sh` (also in the gate) stub `xcrun`/`defaults`/`make`/`open`/`osascript` on `PATH`. `scripts/*.sh` are `#!/bin/bash` with `set -euo pipefail`, mode `100755`, plural `run-devices.sh` name kept (the `r` fish alias calls it).

## Signing / platform declarations

- `DEVELOPMENT_TEAM = 6NWX2DHB9Q`; bundle id `app.alanvardy.CheckStitch`; App Group `group.app.alanvardy.CheckStitch`. The values in the Makefile are the working ones — never re-derive from `~/Library/Developer/Xcode`.
- Entitlements live in `CheckStitch/AppGroup.entitlements` (app target only; no entitlements on the watch target): `com.apple.security.application-groups` + `com.apple.developer.ubiquity-kvstore-identifier`.
- `GENERATE_INFOPLIST_FILE = YES` on all targets → any Info.plist key must be declared as an `INFOPLIST_KEY_*` build setting in `project.pbxproj` (e.g. `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` = "CheckStitch needs access to create reminders.", `project.pbxproj:502-503,547-548`), plus matching `InfoPlist.strings` per locale in `CheckStitch/{en,de,es,fr,ja,zh-Hans}.lproj/`. A new platform key needs both the pbxproj setting and the localized strings (enforced by `LocalizationTests`).

## Unit-suite conventions (Swift Testing, macOS-hosted)

- Suite shape: `struct <Thing>Tests` with `@Test`/`#expect`, behaviour-named functions (never `test`-prefixed), `@Test(arguments:)` for cases; `@MainActor` on any suite touching EventKit or view models (never re-add `SWIFT_DEFAULT_ACTOR_ISOLATION` to test targets).
- Test files import `@testable import CheckStitchCore` where they need internals; the UI smoke stays XCTest.
- Fakes live in `CheckStitchTests/TestFixtures.swift` (`makeItem`, `makeIsolatedDefaults`, `sharedTestEventStore`, `SpyReminderCreator`, `SpyReminderDestination`); also `BackgroundTestFixtures.swift`, `LocalizationFixtures.swift`, `LocalizationTestHelpers.swift` (`String.en` pins `Locale("en")`), `StubBundle.swift`.
- Real-EventKit suites are crash-canaries only (no API assertions): `EventKitReminderCreatorTests` (2), `EventKitReminderDestinationTests` (1). Outcome/string assertions are unit-level, e.g. `ChecklistRemindersTests.swift:165-168` asserts the exact `errorMessage` literals.

## Test-suite inventory

**Unit — `CheckStitchTests/`** (Swift Testing, macOS-hosted):
- Model/store/codec: `ChecklistCodecTests` (20 — version classify/migrate), `ChecklistStoreTests` (76 — save/load/rename/destination/CRUD/coalescing), `ChecklistItemTests` (17 — blank/description decode), `ChecklistItemDateTests` (6 — `dueDateComponents`), `ChecklistMergeTests` (26 — LWW/tombstones).
- Reminder creation: `ChecklistRemindersTests` (13 — run path with `SpyReminderDestination`, incl. zero-creation on missing dest), `ChecklistCreatorTests` (8 — legacy creator with `SpyReminderCreator`), `ReminderListsSnapshotTests` (7 — default-list resolution), `EventKitReminderCreatorTests` (2), `EventKitReminderDestinationTests` (1).
- Sync: `ChecklistSyncCoordinatorTests`, `ChecklistSyncMessageTests`, `ChecklistSyncServiceTests`, `UbiquitousChecklistSyncTests`, `WatchChecklistStoreTests` (11 total), `ChecklistSyncing`-adjacent coverage.
- Views/prefs: `AboutViewTests`, `AppearanceMode*`, `BackgroundFade/ImageStore/PhotoLayer`, `CardPlateTests`, `ChecklistDetailViewTests` (17), `ChecklistExportTests`, `ChecklistImportSessionTests`, `ChecklistViewModelTests`, `ChecklistWidthTests`, `ExportChecklistsViewTests`, `LocalizationTests` (12), `MacWindowFrameTests` (6), `Settings*`, `SmokeTests`, `ViewRenderTests`.

**UI — `CheckStitchUITests/`** (XCTest): one smoke `CheckStitchUITests.testLaunchAndAccessibilitySmoke` — launches, asserts accessibility ids (`createChecklistButton`, `settingsButton`, `emptyStateCreateButton`, `createRemindersButton`), runs an accessibility audit; `#if os(iOS)` guard at line 34. Never asserts message text.

## Platform gating

- `MacWindowFrameTests.swift:1` — whole-file `#if os(macOS)`.
- Inline `#if os(macOS)`: `AboutViewTests:23`, `ChecklistDetailViewTests:60/152/190/206`, `ExportChecklistsViewTests:35`, `ViewRenderTests:27`.
- UI smoke: `os(iOS)` guard. `AppDelegate.swift` and `PhoneSyncAdapter.swift` are whole-file os-gated app-target files (iOS half / `#if os(iOS)` at `PhoneSyncAdapter.swift:1`); `MacAppDelegate` is the macOS half. Watch target references none of them (exclusion by omission in `project.pbxproj:683-729`).
- Core's only `#if os(...)` blocks: `AppearanceMode.swift:3,6,23,35` (iOS/macOS window styling).
- Default actor isolation: app targets set `SWIFT_DEFAULT_ACTOR_ISOLATION`; Core/tests annotate `@MainActor` explicitly.

## Message/UI conventions

- Enums carry their own user-facing text (`ReminderRunOutcome.errorMessage`, `ReminderDestinationTargeting.swift:66-73`; `ChecklistImportError.message`, `ChecklistImportSession.swift:21-27`; `ReminderDestinationError.errorDescription`, `EventKitReminderDestination.swift:53-59`); thrown errors surface via `error.localizedDescription`.
- Alerts: `.alert("<Title>", isPresented: Binding)`, `Button("OK", role: .cancel)`, body `Text(...)`; state-backed `@State` strings gate them (e.g. `runErrorMessage` `ContentView.swift:29`, alert at `:156-163`). Every interactive control carries a camelCase `.accessibilityIdentifier(...)`. The XCTest smoke depends on these ids — new UI must keep them.
- Runtime UI strings are Swift literals or `String(localized:, table: "Localizable", bundle:)` catalog keys; Info.plist strings are per-locale `InfoPlist.strings` + pbxproj keys (see Signing above; `LocalizationTests` enforces the required per-language key set).

## Gotchas

- New files under `CheckStitch/` need **no** `project.pbxproj` edit (project uses `PBXFileSystemSynchronizedRootGroup`).
- Never leave a bare `name=` xcrun destination in a script (wedges parallel agents on shared devices); resolve watch/device names to identifiers.
- SwiftUI/Apple API existence is verified by compiling (`make build` / `make test-unit`), never by mining SDK `.swiftinterface` files.
- Reference implementation for Reminders/EventKit work: `/Users/vardy/dev/SingleThread` (incl. the only on-machine `AppIntent` precedent at `SingleThreadCore/Sources/SingleThreadCore/ReminderIntents.swift`).