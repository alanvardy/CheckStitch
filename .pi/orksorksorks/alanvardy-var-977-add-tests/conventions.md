# Conventions — shared factual appendix for Design, Structure, Plan

All paths relative to their repo root: `CS/` = `/Users/vardy/dev/alanvardy-var-977-add-tests`, `ST/` = `/Users/vardy/dev/SingleThread`.

## Canonical commands

### CheckStitch (`CS/`)
- `make build` — `xcodebuild -scheme 'CheckStitch' -destination '<SIM>' -configuration 'Debug' -derivedDataPath 'DerivedData' build` (`Makefile:14-18`). Destination precedence (`Makefile:2-6`): explicit `SIM=` > `.simulator_id` (this worktree: UDID `845FFF19-...`; `.simulator_id`) > `platform=iOS Simulator,name=iPhone 17`.
- `make run` — `build` then `bash scripts/run-simulator.sh '$(SIM)' '$(APP)'` (`Makefile:19-20`); boot/install/launch via `xcrun simctl` (`scripts/run-simulator.sh:55-63`).
- `make clean`.
- **Gate: `CS/scripts/test.sh`** — `make build` + `shellcheck scripts/*.sh` (fallback `bash -n` per script) (`scripts/test.sh:9-14`); prints `gate: ok` (`:17`). There is **no test target**; `CS/AGENTS.md:14-15` says don't add one "as part of a small task".
- Real-device: `bash scripts/run-devices.sh` (iOS: `generic/platform=iOS` + `-allowProvisioningUpdates` `scripts/run-devices.sh:58-63`, then `devicectl device install`/`launch` `:76-81`; macOS: `CODE_SIGNING_ALLOWED=NO` `:112-121`, controlled by `RUN_MAC`).
- Env overrides honoured by Makefile/scripts: `SCHEME`, `BUNDLE_ID`, `CONFIGURATION`, `DERIVED_DATA` (`AGENTS.md:12-13`).

### SingleThread (`ST/`) — the model repo
- `make build` → `xcodebuild ... build-for-testing` (`Makefile:26-27`).
- `make test` → `./scripts/test.sh --unit-only` (`Makefile:87`); `make ui-test` → `--ui-only` (`:90`); `make check` → full `./scripts/test.sh` (`:112`).
- `make mac-test` → macOS-host unit run with `CODE_SIGNING_ALLOWED=NO` (`Makefile:35-36`).
- `make coverage` / `coverage-ui` / `coverage-all` → `-enableCodeCoverage YES [-only-testing:<suite>] test -resultBundlePath build/<Name>.xcresult` + `xcrun xccov view --report <result>` (`Makefile:49-83`).
- `make watch-test` / `watch-ui-test` → `xcodebuild -scheme SingleThreadWatch ... -only-testing:SingleThreadWatch(UITests)` (`Makefile:96-109`).
- `make lint` (`Makefile:118-119`); `make periphery` → `periphery scan --strict -- -destination "$(SIM)"` (`:126-127`).
- `ST/scripts/test.sh` full gate order: resolve/preboot sim (`:27-48`), `.simulator_id` handling (`:51-66`), prune stale XCTest runtimes (`:78-107`), verify_deployment_target (`:124-217`), swiftformat check (`:221, 226`), swiftlint `--strict` (`:230`), iOS `build-for-testing` (`:234`), watch build (`:242`), periphery `--skip-build` (`:250-252`), iOS UI `test-without-building -only-testing:SingleThreadUITests` (`:254-260`), watch UI + `lib_TestingInterop.dylib` embed (`:262-290`), watch unit (`:292-297`), macOS unit (`:300-306`). Modes `--unit-only` (`:315-321`) / `--ui-only` (`:329-343`).
- `ST/scripts/test-one.sh` — single `<Target/Suite/case>` with `-resultBundlePath`; `xcrun xcresulttool get test-results summary` (`:57`); exit non-zero if 0 cases ran.
- CI (`ST/.github/workflows/ci.yml`, push→main): `unit-tests` `:12-77` uses `-parallel-testing-enabled NO` + `-resultBundlePath TestResults.xcresult`; `ui-tests-smoke` `:80-139`; `mac-tests` `:141-190` (`CODE_SIGNING_ALLOWED=NO`); `lint` `:193-238`; `watch-ui-tests` `:240-309` (creates its own dedicated watch sim `:262-271`); `secret-scan` (gitleaks) `:311-328`.

## Test-suite inventory (SingleThread — the reference layout)

### `ST/SingleThreadTests/` (~80 Swift files) — unit tests, Swift Testing in `import Testing`
- Framework: `struct <Thing>Tests` suites; `@MainActor` on 54/80 (all EventKit-touching ones); `@Suite(.serialized)` for shared-state suites (30 uses, all serialized); `@Test(arguments: [...])` parametrization; `#expect(v == e [, "msg"])`, `try #require(...)` assertions; behavior-past-tense names, never `test`-prefixed.
- Coverage anchors: `ReminderStoreTests` (70 @Test), `SkippedReminderSyncServiceTests` (36), `ReminderDictationParserTests` (34), `EventKitStoringTests` (23), `UITestingSeedTests` (20), `SingleThreadTests.swift:11-21` (20 view-render smoke tests), plus small suites (AppearanceMode, CardWidth, SortOption, Localization …).
- Fixtures in this package: `TestFixtures.swift` (global `@MainActor sharedTestEventStore` :11 — one store kept alive because `EKReminder` weakly references it :6-9 — plus `makeReminder`/`makeCalendar`/`inListReminder`/`FakeSession` `#if os(iOS)||os(watchOS)` :59-97/`TestFakeTranscriber`/fetch fakes/FetchGate), `BackgroundTestFixtures.swift`, `LocalizationTestHelpers.swift`, `StubBundle.swift`, `UITestingSeedTests.swift`.
- Per-file `.swiftlint.yml` in `ST/SingleThreadTests/` relaxes `force_unwrapping`.

### `ST/SingleThreadWatchTests/` (8 files) — watch unit tests (Windows `@Suite(.serialized)`)
- Own `TestFixtures.swift`: `sharedWatchEventStore` (:10), `watchReminder(_:)` (:15-18), `WatchFakeSession` (:22-37). Covers sync pipeline, viewmodel/glow states.

### `ST/SingleThreadUITests/` + `ST/SingleThreadWatchUITests/` — XCTest UI smoke
- `SingleThreadUITests.swift`: `import XCTest`, `XCTestCase`, `setUpWithError` (:8, 10, 21); accessibility audit via `performAccessibilityAudit`.
- Platform gating: unit suites run on macOS host (`-only-testing:SingleThreadTests`, `CODE_SIGNING_ALLOWED=NO`); iOS UI on prebooted sim (`build-for-testing` → `test-without-building`); watch suites on dedicated watch sim with local `lib_TestingInterop.dylib` embed (test.sh:262-290).
- Registration/discovery: `.xctest` wrappers `ST/project.pbxproj:92-97`, test targets `:116-123`, folder-sync sources (`PBXFileSystemSynchronizedRootGroup` `:110-117`); scheme TestActions in `ST/SingleThread.xcscheme:39-69` (`shouldAutocreateTestPlan="YES"`, parallelizable references to `SingleThreadTests.xctest` / `SingleThreadUITests.xctest`).

### CheckStitch
- **No tests, no fixture files** — nothing under `CS/` corresponds to any of the above.

## Build/verify gotchas
- **Destination discipline (both repos):** never a bare `name=` destination — it selects a shared device and wedges parallel agents (`CS/AGENTS.md:17-18`); preflight `SIM`/`resolve_sim_udid` exists in ST test.sh (`:27-38`).
- **macOS runs unsigned:** `CODE_SIGNING_ALLOWED=NO` everywhere macOS is a target (`ST/Makefile:35-36`, `ST/scripts/test.sh:300-306`, `CS/scripts/run-devices.sh:112-121`) — the Mac provisioning profile lacks the CheckStitch App Group entitlement (`CS/scripts/run-devices.sh:1-40`).
- **Info-plist requirements (`GENERATE_INFOPLIST_FILE = YES`** `CS/project.pbxproj:261, 303`**):** `INFOPLIST_KEY_NSRemindersUsageDescription`/`NSRemindersFullAccessUsageDescription` keys must exist in the pbxproj build settings (`CS/project.pbxproj:262-263, 304-305`) — keys are pbxproj-only, never Swift strings.
- **Actor isolation:** `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` on app/watch targets (`CS/project.pbxproj:284, 326`; ST app/watch scheme), **not** on test targets; test code opts in per-suite via `@MainActor`; pure math escapes via `nonisolated` (`CS/CheckStitch/ContentView.swift:147-150`); fakes need `@unchecked Sendable` under Swift 6 warnings-as-errors (ST `StubBundle.swift:4-7`).
- **SwiftFormat `preferSwiftTesting`:** unit-test function names must NOT start with `test`/`testing` — SwiftFormat strips those prefixes in ST (AGENTS.md), so behavior-named functions are required.
- **Gate staging:** ST runs the full `./scripts/test.sh` only once after all phases commit (via `run-gate` skill, worktree, multi-hour timeout); workers use targeted checks only. CheckStitch gate is `CS/scripts/test.sh` (build + shellcheck) — currently the only gate.
- **Simulator lifecycle:** ST pre-boots the sim and prunes stale `~/Library/Developer/XCTestDevices` runtimes (test.sh:27-48, 78-107); CI uses `-parallel-testing-enabled NO` (`ci.yml:56-71`).
- **Deployment-target literals:** ST `verify_deployment_target` (test.sh:124-217) greps `(IPHONEOS|MACOSX|WATCHOS)_DEPLOYMENT_TARGET` literals in pbxproj/Package.swift with alias-count checks; drift exits 1.
- **Result bundles:** coverage via `xcrun xccov view --report` (ST `Makefile:56, 71, 83`); single-test summary via `xcrun xcresulttool get test-results summary` (ST `scripts/test-one.sh:57`).
- **Signing values (CS):** `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle id `app.alanvardy.CheckStitch`, App Group `group.app.alanvardy.CheckStitch`; on machines without the provisioning profile add `-allowProvisioningUpdates` (`CS/AGENTS.md:20-23`).
- **Shell environment:** both AGENTS.md files record that the command tool runs fish — heredocs, `VAR=`, loops, unquoted globs fail; write `/tmp/x.sh` + `bash /tmp/x.sh`, or a single `bash -c '...'` for read-only agents.