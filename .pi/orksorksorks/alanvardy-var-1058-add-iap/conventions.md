# Conventions — CheckStitch

Shared factual appendix: build/test/gate commands, test-suite inventory, and gotchas
that Design/Structure/Plan rely on instead of re-reading `Makefile`/`scripts`/AGENTS.md.

## Build / test / gate commands

- **Gate:** `./scripts/test.sh` — `make build` (simulator) → headless pre-boot of this
  worktree's `.simulator_id` → `make test` → `make build-mac` → `make watch-build` →
  `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`, prints `gate: ok`.
  Every compiling leg passes shared `WARNINGS_AS_ERRORS` (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
  GCC_TREAT_WARNINGS_AS_ERRORS=YES`) so a warning fails the gate (`AGENTS.md` Build/run;
  `scripts/tests/run.sh` pins it per leg).
- **`make build`** — simulator build (scheme `CheckStitch`).
- **`make build-mac`** — unsigned macOS compile leg (the gate's platform check; no signing).
- **`make build-mac-signed`** — runnable macOS app, signed with DEVELOPMENT_TEAM so
  `AppGroup.entitlements` (incl. KVS id) is embedded; needs `-allowProvisioningUpdates`.
- **`make test-unit`** — runs `CheckStitchTests` on `platform=macOS` with
  `CODE_SIGNING_ALLOWED=NO` (no sim, no signing). Fast pre-gate verification.
- **`make test-ui`** — exactly one `CheckStitchUITests` smoke via `build-for-testing` →
  `test-without-building` on this worktree's `.simulator_id`.
- **`make watch-build`** / **`bash scripts/run-watch.sh`** — watchOS compile/install (unsigned,
  sim-free; the watch resolved by identifier, never a bare name).
- **`bash scripts/run-devices.sh`** — real-device install/launch (Developer Mode; prefers an
  iPhone) + host Mac + paired Watch (`RUN_WATCH=0` skips watch). Honours `SCHEME`/`BUNDLE_ID`/
  `CONFIGURATION`/`DERIVED_DATA`.
- **`make run`** — build + boot/install/launch on the resolved simulator.
- Destination precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared default.
  **Never** leave a bare `name=` simulator destination (selects a shared device, wedges parallel
  agents). The gate takes a bounded host lock, quits `Simulator.app` once, pre-boots the
  worktree's UDID between `make build` and `make test`, releases the lock after; `LOCK_TIMEOUT`
  (60) bounds the wait. Missing `.simulator_id` → skip; unresolvable → hard error.

## Test-suite inventory

Unit + UI suites (Swift Testing for `CheckStitchTests`, one XCTest for `CheckStitchUITests`):

| Path | Covers | Platform gating |
|------|--------|-----------------|
| `CheckStitchTests/ChecklistCreatorTests.swift` | Core `ChecklistCreator` reminder policy over `ReminderCreating` | macOS-hosted |
| `CheckStitchTests/ChecklistRemindersTests.swift` | App seam `ChecklistReminders.create` sequencing/outcomes | macOS-hosted |
| `CheckStitchTests/ChecklistRunViewModelTests.swift` | `ChecklistRunViewModel` (uses `FetchGate`) | `#if os(iOS)`? — `@MainActor`, EventKit-touching |
| `CheckStitchTests/ChecklistStoreTests.swift` | `ChecklistStore` load/save/sync persistence | macOS-hosted |
| `CheckStitchTests/UbiquitousChecklistSyncTests.swift` | KVS `UbiquitousChecklistSync` read/write/observe | macOS-hosted |
| `CheckStitchTests/MacWindowFrameTests.swift` | macOS window framing | `#if os(macOS)` (`:1`) |
| `CheckStitchTests/InterfaceSettingsViewTests.swift` | settings UI | `#if os(iOS)`/`#if os(macOS)` (`:12,29`) |
| `CheckStitchTests/BackgroundImageStoreTests.swift` | background image store | macOS-hosted |
| `CheckStitchTests/WatchChecklistStoreTests.swift` | watch store/transport | macOS-hosted (`@testable import`) |
| `CheckStitchTests/ChecklistDetailViewTests.swift` | detail-view two-step delete gate | macOS-hosted |
| `CheckStitchUITests/CheckStitchUITests.swift` | single `testLaunchAndAccessibilitySmoke` (`:34`) | XCTest, `platform=...` smoke |

- **Fixtures/fakes** live in `CheckStitchTests/TestFixtures.swift` (`makeIsolatedDefaults`,
  `SpyReminderCreator`, `SpyReminderDestination`, `InMemoryChecklistSync`, `@MainActor
  sharedTestEventStore`) and `CheckStitchTests/BackgroundTestFixtures.swift` (`FetchGate`).
- Tests use `@testable import CheckStitch` / `@testable import CheckStitchCore`. Test targets
  deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with `@MainActor`.
- Suites are `struct <Thing>Tests`, `@Test`/`#expect`, behaviour-named methods (`@Test(arguments:)`
  for cases), `@Suite(.serialized)` where shared.

## Build / verify gotchas

- **Warnings-as-errors** means any new warning fails the gate — compile locally via `make build`
  / `make test-unit` before the full gate.
- New files under `CheckStitch/` need no `project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`);
  files added to `CheckStitchCore` may need `Package.swift` target membership if not globbed.
- **One test process at a time**: `make test-ui` and the simulator gate use a single shared
  `.simulator_id`; parallel agents must not both touch Simulator.app (bounded lock protocol).
- `CheckStitchCore` has **no Tests/ dir**; unit suites the package are hosted by the macOS
  `CheckStitchTests` target via `@testable import`, not `swift test`.
- watchOS EventKit is read-only; EventKit-using remote runs never commit on watch
  (`#if !os(watchOS)` save guard in `EventKitReminderDestination.swift:55-58`).
- `GENERATE_INFOPLIST_FILE = YES`; any new `Info.plist` usage-description key must be declared in
  build settings, not the plist.
- Verifying on a real device needs Developer Mode + `devicectl`/`run-devices.sh`; icon/render
  tickets can't close on static evidence — inspect the installed bundle and state what the user
  should see.