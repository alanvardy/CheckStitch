# Conventions

Shared factual appendix for Design/Structure/Plan — build, test, and verify
facts for the CheckStitch repo, so later phases do not re-open the Makefile,
gate scripts, or test suite. All paths relative to the repo root.

## Canonical commands

| Command | What it does | Notes |
|---|---|---|
| `make build` | iOS Simulator build via xcodebuild (`Makefile:17-24`) | `-destination $(SIM)`, Debug, `DerivedData` |
| `make build-mac` | Unsigned macOS compile leg (`Makefile:30-37`) | `CODE_SIGNING_ALLOWED=NO`, platform=macOS |
| `make build-mac-signed` | Runnable signed macOS app (`Makefile:40-47`) | `-allowProvisioningUpdates`; needs team profile; used by run-devices.sh |
| `make watch-build` | watchOS Simulator unsigned compile (`Makefile:50-55`) | `generic/platform=watchOS Simulator`, sim-free |
| `make run` | build + `scripts/run-simulator.sh` boot/install/launch (`Makefile:57-58`) | needs a resolvable sim UDID |
| `make test` | `test-unit` + `test-ui` aggregate (`Makefile:60-62`) | |
| `make test-unit` | macOS-hosted unit tests, unsigned (`Makefile:64-72`) | `-only-testing:CheckStitchTests`, `CODE_SIGNING_ALLOWED=NO`; fast sanity leg |
| `make test-ui` | UI smoke: `build-for-testing` then `test-without-building -only-testing:CheckStitchUITests` (`Makefile:75-86`) | destination `$(SIM)`; exactly one smoke case |
| `make clean` | `xcodebuild … -destination $(SIM) clean` (`Makefile:88-89`) | |
| `bash scripts/test.sh` | The full gate (see below) | prints `gate: ok` (`scripts/test.sh:109`) |
| `bash scripts/tests/run.sh` | Shell-suite tests against stubbed host tools | standalone-run or gate step 6 |
| `shellcheck scripts/*.sh scripts/tests/*.sh` | shell lint (gate step 7) | falls back to `bash -n` if shellcheck missing |
| `make test-unit` first, then `bash scripts/test.sh` | recommended verify cadence | gate is the acceptance gate |

### Gate flow (`scripts/test.sh`, order)
1. Resolve destination: `SIM` env → `.simulator_id` → none (`:17-33`); UDID via `resolve-sim-udid.sh --require-id` (`:27-28`; `name=` forms rejected, `scripts/resolve-sim-udid.sh:13-18, :26-30`).
2. `make build` (`:35`).
3. Acquire `${TMPDIR:-/tmp}/checkstitch-simulator.lock` (`:44-67`; stale-PID reaping `:52-58`; `LOCK_TIMEOUT` default 60s degrade `:59-62`).
4. EXIT trap: release lock + `simctl shutdown $GATE_UDID` only (`:69-81`); `osascript` Simulator quit, errors swallowed (`:73`).
5. Pre-boot `simctl boot` + `bootstatus -b` if a UDID resolved (`:75-80`); else warn and continue.
6. `make test` (`:82`); release lock (`:83`).
7. `make build-mac` (`:89-90`), `make watch-build` (`:95`).
8. `scripts/tests/run.sh` unless `GATE_TESTS_SKIP=1` (`:97-99`).
9. shellcheck or `bash -n` (`:101-107`); `echo "gate: ok"` (`:109`).

### Gate/env overrides
- `SIM` — explicit destination, wins over `.simulator_id` (`Makefile:5`; `scripts/test.sh:19-20`).
- `SIM_ID_FILE` — overrides the `.simulator_id` path (`scripts/test.sh:7`).
- `LOCK_TIMEOUT` — seconds, bounds lock wait (`scripts/test.sh:45`).
- `GATE_TESTS_SKIP=1` — skips the shell suite (`scripts/test.sh:97`).
- `TMPDIR` — relocates the lock dir (used by tests to isolate, `scripts/tests/run.sh:142-150`).
- `DERIVED_DATA`, `CONFIGURATION`, `SCHEME`, `WATCH_SCHEME`, `BUNDLE_ID` — Makefile/env overrides used by run scripts (`Makefile:8-13`; `scripts/run-devices.sh`, `scripts/run-watch.sh`).

## Test-suite inventory

### `CheckStitchTests` — one macOS-hosted unit bundle, two styles
- **Swift Testing** (`struct …Tests`, `@Test`/`#expect`), all under `CheckStitchTests/`:
  - Canary: `SmokeTests.swift:4-6`.
  - Models/logic: `ChecklistItemTests.swift:5`, `ChecklistMergeTests.swift:7`, `ChecklistItemDateTests.swift:5`, `ChecklistCreatorTests.swift:6`, `ChecklistViewModelTests.swift:5`, `ChecklistWidthTests.swift:5`.
  - Sync/KVS: `ChecklistSyncServiceTests.swift:7`, `UbiquitousChecklistSyncTests.swift:5`, `ChecklistSyncCoordinatorTests.swift:6`, `ChecklistSyncMessageTests.swift:5`, `WatchChecklistStoreTests.swift:6`.
  - EventKit: `EventKitReminderCreatorTests.swift:6`, `EventKitReminderDestinationTests.swift:6`, `ReminderListsSnapshotTests.swift:6`, `ChecklistRemindersTests.swift:7`.
  - UI/render: `ViewRenderTests.swift:7`, `CardPlateTests.swift:8`, `ChecklistDetailViewTests.swift:14`, `ExportChecklistsViewTests.swift:11`, `AboutViewTests.swift:9`, `BackgroundFadeTests.swift:7`, `BackgroundImageStoreTests.swift:9`, `BackgroundPhotoLayerTests.swift:8`, `MacWindowFrameTests.swift:7`.
  - Settings/appearance/localization: `AppearanceModeTests.swift:5`, `AppearanceModePreferenceTests.swift:5`, `SettingsBindingsTests.swift:7`, `SettingsDataActionQueueTests.swift:8`, `LocalizationTests.swift:7`, `AppInfoTests.swift:8`, `ChecklistImportSessionTests.swift:7`, `HarnessTests.swift:4`.
- **XCTest** (store/codec/export trio): `ChecklistStoreTests.swift:5-6`, `ChecklistCodecTests.swift:6`, `ChecklistExportTests.swift:6` — suite-level pins usable, e.g. `-only-testing:CheckStitchTests/ChecklistStoreTests` (prior evidence: `.pi/…/alanvardy-var-971-sync-with-icloud/plan.md:274, :747`).
- Platform: macOS host only (`make test-unit`), unsigned, no simulator boot. `@MainActor` opted in per-suite where EventKit/view-model is touched — test targets do not set `SWIFT_DEFAULT_ACTOR_ISOLATION` (repo AGENTS.md).

### `CheckStitchUITests` — one bundle, one smoke case
- `CheckStitchUITests/CheckStitchUITests.swift:14` `testLaunchAndAccessibilitySmoke`; `:6` `runsForEachTargetApplicationUIConfiguration=false`; `:9` `continueAfterFailure=false`; `:12` `@MainActor`; `:34-37` `#if os(iOS)` accessibility audit.
- Platform: iOS Simulator via `$(SIM)`; runs via `build-for-testing` → `test-without-building` (`Makefile:75-86`). Keep `-only-testing` scoping.

### Shell suites — `scripts/tests/run.sh`
- `new_stubs` (`:20-34`) + `stub_gate_command` (`:87-98`): no-op logging stubs for `make xcrun defaults open osascript` on a temp PATH.
- Gate cases (`:99-160`) run the real gate with private `TMPDIR`/`SIM_ID_FILE`; watch cases (`:163-226`) stub `xcrun devicectl`; pbxproj entitlement regression (`:241-262`).
- Runs standalone; exit nonzero on any failure (`:263-264`).

## Schemes
- Committed: `CheckStitch.xcodeproj/xcshareddata/xcschemes/CheckStitch.xcscheme` and `CheckStitchWatch.xcscheme` (only two; no `.xctestplan` files).
- `CheckStitch.xcscheme`: `shouldAutocreateTestPlan="YES"` (`:25-30`); both testables `parallelizable="NO"` (`:32-42`, `:43-53`); no `-only-testing:` in scheme (Makefile-side: `Makefile:70`, `Makefile:85`).
- New files under `CheckStitch/` or `CheckStitchTests/` need no `project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`).

## Build/verify gotchas
- **Destination precedence**: explicit `SIM=` > worktree `.simulator_id` (`Makefile:4-5`); `--require-id` refuses bare `name=` (gate pre-boot path). Never leave a bare `name=` destination in a script — selects a shared device and wedges parallel agents.
- **`.simulator_id` is gitignored** (`.gitignore:13-14`) — never commit it; a hosted runner has no such file, and the gate then skips pre-boot/shutdown.
- **Simulator window/parallelism**: host lock bounds concurrent gate windows (`scripts/test.sh:44-67`); shutdown is scoped to the resolved UDID, never `all`/`booted` (`:69-71`). On virtualized runners, disable test parallelism (`-parallel-testing-enabled NO -maximum-concurrent-test-simulator-destinations 1`) and consider `-retry-tests-on-failure` for UI (SingleThread ci.yml:56-71, :124-138).
- **Signing**: `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch` (repo AGENTS.md). CI precedent neutralizes via `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV` (SingleThread ci.yml:28-29, :153-154) and `CODE_SIGNING_ALLOWED=NO` for macOS legs. `build-mac-signed` is the only target needing a real profile.
- **Gate host-dependence**: pre-boot/`osascript`/lock are local-tooling concerns; the portable gate legs are `make build`, `make test-unit`, `make build-mac`, `make watch-build`, `scripts/tests/run.sh`, shellcheck.
- **Runner/Xcode precedent**: `macos-26` + `maxim-lobanov/setup-xcode@v1` with `xcode-version: '26.6'` (SingleThread ci.yml:23-26); DerivedData cache keyed on `hashFiles(...)` (SingleThread ci.yml:31-38).
- **CheckStitch has no committed CI/dependabot config today**; its only CI is out-of-repo Xcode Cloud (`docs/TestFlight-xcode-cloud.md:4, :44-47, :115-116`).
- **Gate step 7 lint**: shellcheck if installed, else `bash -n` (`scripts/test.sh:101-107`) — a CI workflow wanting strict lint must install shellcheck.