# Conventions

Shared appendix for Design / Structure / Plan. Everything here is a factual
command, inventory, or gotcha — no design decisions.

## Canonical commands

- **The gate**: `./scripts/test.sh` — order: `make build` (simulator, `WARNINGS_AS_ERRORS`) → headless pre-boot of this worktree's `.simulator_id` sim → `make test` → `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`. Prints `gate: ok`. Takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`).
- **Fast unit leg**: `make test-unit` — `CheckStitchTests` on `platform=macOS`, `CODE_SIGNING_ALLOWED=NO`, `-only-testing:CheckStitchTests`. (Always run this before the full gate.)
- **Fast simulator build**: `make build` — scheme `CheckStitch`, destination from `.simulator_id`, `WARNINGS_AS_ERRORS`.
- **macOS compile leg**: `make build-mac` (unsigned, `CODE_SIGNING_ALLOWED=NO`); signed/many-tuned: `make build-mac-signed` (needs `-allowProvisioningUpdates`, already in target).
- **Watch platform compile**: `make watch-build` (scheme `CheckStitchWatch`, `generic/platform=watchOS Simulator`, unsigned).
- **UI smoke**: `make test-ui` — one XCTest case, build-for-testing → test-without-building on this worktree's `.simulator_id` sim.
- **Everything else**: `make run` (build + boot sim + launch), `bash scripts/run-devices.sh` (real device + host + watch; `RUN_WATCH=0` to skip watch), `bash scripts/run-watch.sh` (paired watch).
- **Localization pre-check**: `bash scripts/l10n-check.sh` before touching `Localizable.xcstrings`.

### Test targets (Makefile:122-164)
- `test: test-unit test-ui` (`Makefile:128`).
- `test-unit` (`:130-138`): `-only-testing:CheckStitchTests` on macOS host, unsigned, no sim.
- `test-ui` (`:140-154`): builds-for-testing then `-only-testing:CheckStitchUITests test-without-building` on the worktree sim.

## Warnings-as-errors

- `WARNINGS_AS_ERRORS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES` (`Makefile:24-31`), applied to `build`, `build-mac`, `watch-build`, `test-unit`, `test-ui`. **A compiler warning fails the gate.** `build-mac-signed`, `run-watch.sh`, `run-devices.sh` are deliberately outside enforcement. `scripts/tests/run.sh` pins the enforced legs (`warnings_as_errors_reaches_compiling_legs`).

## Destination / simulator gotchas

- Destination precedence: explicit `SIM=` > this worktree's `.simulator_id` > shared default (`Makefile:6-7`). **Never leave a bare `name=` destination in a script** — it selects a shared device and wedges parallel agents.
- `make run` opens a Simulator window pinned to the resolved UDID (`open -a Simulator --args -CurrentDeviceUDID <udid>`). Windows appertain to the device, not the worktree — multiple worktrees/boots can share a Simulator.app.
- Gate holds a host lock, pre-boots this worktree's UDID headlessly between `make build` and `make test`, releases lock + shuts down that UDID on exit (EXIT trap). Stale lock (dead PID) is reaped. `LOCK_TIMEOUT` default 60. Missing `.simulator_id` → skip; present-but-unresolvable → hard error. Shutdown scoped to the resolved UDID only.
- `make test-ui` runs exactly one smoke case on this worktree's `.simulator_id`.

## Test-suite inventory (`CheckStitchTests/`, macOS-hosted)

- Swift Testing suites (`struct` + `@Test`, `@MainActor` where they touch EventKit/view-model): `ChecklistItemTests`, `ChecklistMergeTests`, `ChecklistDetailViewTests`, `CheckListListViewModelTests` (note casing), `ChecklistSyncServiceTests`, `WatchChecklistStoreTests`, `LocalizationTests`, `LocalizedStringResolutionTests`.
- XCTest suites (`XCTestCase`, `@MainActor`): `ChecklistStoreTests.swift` (fresh isolated `UserDefaults` per test; `textEditDelay: nil`; deterministic `Clock`).
- UI smoke: `CheckStitchUITests/CheckStitchUITests.swift` — `testLaunchAndAccessibilitySmoke()` (launch, `settingsButton`, empty state, a checklist row action).
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION` → suites opt in per-suite with `@MainActor`.
- Fixtures: `CheckStitchTests/TestFixtures.swift` (`makeItem`, `makeIsolatedDefaults()`, `@MainActor sharedTestEventStore`, spy doubles `SpyReminderCreator`/`SpyReminderDestination`/`InMemoryChecklistSync`/`FakeChecklistSyncTransport`/`SpyChecklistRunner`/`SpyPurchaseProvider`, `TestError.boom`); `BackgroundTestFixtures.swift`, `LocalizationFixtures.swift`, `StubBundle.swift`, `LocalizationTestHelpers.swift`.

## Localization constraints

- Catalogs: `CheckStitch/Localizable.xcstrings` (App), `CheckStitchWatch/Localizable.xcstrings` (Watch), `CheckStitchCore/.../Resources/Localizable.xcstrings` (Core). `.lproj` holds only `InfoPlist.strings`.
- Every key needs **all six languages** `en, de, es, fr, ja, zh-Hans`.
- A new user-facing key must be added **both** to the `.xcstrings` catalog **and** to `CheckStitchTests/LocalizationFixtures.swift` `requiredKeys` for its catalog, or `LocalizationTests.everyRequiredKeyIsPresent` fails.
- `LocalizationTests.catalogsHaveAllSixLanguages` fails on missing/empty translation in any language.
- `LocalizationTests` non-English-differs canary forces non-English values to differ from English (allow-list `excludedIdentities` in `LocalizationFixtures.swift`).

## Build/verify gotchas surfaced by research

- **`ChecklistStore` is the sole encoder/persister** (`envelope` getter); sync transport (`ChecklistSyncing`) is opaque `Data`.
- **Merge is explicit per-field**: adding a scalar relationship field requires an explicit copy line in `ChecklistMerge.mergedChecklists` (`ChecklistMerge.swift:65-67`); transport/coordinator don't need changes unless the field has its own clock.
- **Reorder is local-first, no revision bump** (store `moveChecklists`); item reorder does stamp `orderRevision`/`orderModifiedAt`.
- New files under `CheckStitch/`, `CheckStitchCore/`, `CheckStitchTests/`, `CheckStitchWatch/` need **no** `project.pbxproj` edit (`PBXFileSystemSynchronizedRootGroup`).
- Warnings are errors on every compiling gate leg — run `make build` / `make test-unit` after edits before the full gate.