# Conventions

Shared factual appendix for Design/Structure/Plan: canonical commands, test
inventory and platform gating, and build/verify gotchas.

## Canonical commands

- `make build` — `xcodebuild -scheme CheckStitch -destination $(SIM) Debug`, derivedDataPath `DerivedData` (Makefile:15-20).
- `make build-mac` — macOS build with `CODE_SIGNING_ALLOWED=NO` (Makefile:24-30).
- `make run` — build + `bash scripts/run-simulator.sh $(SIM) $(APP)` (Makefile:33).
- `make test-unit` — `-destination platform=macOS -only-testing:CheckStitchTests test` with `CODE_SIGNING_ALLOWED=NO` (Makefile:39-47).
- `make test-ui` — `build-for-testing` then `test-without-building`, `-only-testing:CheckStitchUITests` (Makefile:49-56).
- `make test` — test-unit + test-ui (Makefile:35). `make clean` (Makefile:59).
- **Gate**: `bash scripts/test.sh` — `make build`, `make test`, `make build-mac`, `shellcheck scripts/*.sh` (`bash -n` fallback), prints `gate: ok` (scripts/test.sh:4-28).
- `scripts/run-simulator.sh:1-62` — resolves UDID from `id=`/`name=` (:18-29), `xcrun simctl boot/bootstatus` (:37-38), install, launch with `--terminate-running-process`; bundle id default `app.alanvardy.CheckStitch` (:11, :44).
- `scripts/run-devices.sh:1-150` — devicectl discovery (embedded python3 parse :30-90), per-device generic build (:104-111), install + launch (:116-126), macOS step via build-mac (:130-141); env overrides `SCHEME`/`BUNDLE_ID`/`CONFIGURATION`/`DERIVED_DATA`/`RUN_MAC`.
- SIM destination precedence (Makefile:2-5): explicit `SIM=` > this worktree's `.simulator_id` > shared `name=iPhone 17` default. `MAC_SIM := platform=macOS` (:6).
- Scripts are `#!/bin/bash` with `set -euo pipefail`, committed mode 100755.

## Test-suite inventory

All under `CheckStitchTests/` unless noted; Swift Testing with behaviour-named functions (`@Test`, `#expect`), macOS-hosted via test-unit:

| File | Coverage | Gating |
|---|---|---|
| `SmokeTests.swift:4-8` | harness canary (macOS unit target runs, links CheckStitchCore) | — |
| `ChecklistCreatorTests.swift:7-59` | blank-title skip, non-blank count, all-blank no-op, permissionDenied, accessError→failed, save-throw→failed | `@MainActor` (:5) |
| `ChecklistViewModelTests.swift:6-56` | seeded items, created flag, spinner toggling via `onCreate` hook, denial/failure flags | `@MainActor` |
| `EventKitReminderCreatorTests.swift:13-15` | construction canary over sharedTestEventStore; no EventKit API called | `@MainActor` |
| `ChecklistStoreTests.swift` (XCTestCase) | create/reload, rename persists, add/remove item, delete-only-target, unknown-id no-op, corrupt→empty, corrupt repaired on save, unsupported version untouched, coalesced edits + flush, structural save cancels pending text edit | `@MainActor`, `textEditDelay: nil` for sync saves |
| `ChecklistCodecTests.swift:1-30` (XCTest) | envelope round-trip, unknown version→empty, empty envelope, classify unsupported vs unreadable | — |
| `ChecklistItemTests.swift:5-6` | stable identity for duplicate titles | — |
| `AppearanceModeTests.swift:6-14` | valid raw values (argumentized), invalid→system | — |
| `AppearanceModePreferenceTests.swift:6-16` | preference round-trip, ignores unknown stored value | — |
| `ChecklistWidthTests.swift:6-17` | max-width scaling/clamp/boundary | — |
| `ViewRenderTests.swift:7-8` | settings view lists all appearance modes | — |
| `MacWindowFrameTests.swift:1-58` | 6 NSRect tests of `MacAppDelegate.onScreenFrame` | `#if os(macOS)` (:1, :58) |
| `TestFixtures.swift:1-51` | not a test: `makeItem` (:6), `makeIsolatedDefaults` (UUID-suffixed suite, wiped, :10-16), `sharedTestEventStore` (:22-24), `SpyReminderCreator` (:29-51), `TestError` (:44-46) | — |
| `CheckStitchUITests/CheckStitchUITests.swift:1-38` | single smoke: launch, buttons exist, row-action empty-state vs play button, accessibility audit | `#if os(iOS)` on audit (:34-38); `runsForEachTargetApplicationUIConfiguration=false` (:5), `continueAfterFailure=false` (:10) |

## EventKit faking / stubbing conventions

- **No EventKit mocking framework.** Real adapter touched only via construction canary; behaviour tested through `SpyReminderCreator` implementing the `ReminderCreating` seam (`TestFixtures.swift:29-51`): recorded `createdTitles`, injectable `requestAccess`/`create` errors, `onCreate` hook.
- `sharedTestEventStore` must stay alive for the whole session (EKReminder holds a weak store reference; dealloc → SIGTRAP) — held as a `@MainActor` global (`TestFixtures.swift:22-24`).
- UserDefaults isolation via `makeIsolatedDefaults` — never touch `.standard` in store tests.

## Build / verify gotchas

- App targets set `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (project.pbxproj:432, :474) but **test targets deliberately do not** (Makefile:35-37) — suites opt in with `@MainActor`; never add the default there.
- `GENERATE_INFOPLIST_FILE = YES` — there is no Info.plist file; usage descriptions are `INFOPLIST_KEY_NSRemindersUsageDescription` / `INFOPLIST_KEY_NSRemindersFullAccessUsageDescription` (project.pbxproj:410-411, :452-453).
- Unit tests run unsigned on macOS (`CODE_SIGNING_ALLOWED=NO`); UI tests need the pinned simulator from `.simulator_id` — never leave a bare `name=` destination in a script (parallel-agent wedging).
- UI test process is one-shot build-for-testing → test-without-building; changing UI code requires re-running the build-for-testing phase.
- Entitlements: App Group `group.app.alanvardy.CheckStitch` (CheckStitch/AppGroup.entitlements:7, AppGroup.swift:7); `DEVELOPMENT_TEAM = 6NWX2DHB9Q`, bundle `app.alanvardy.CheckStitch`; add `-allowProvisioningUpdates` on machines without the profile; do not re-derive team from Xcode prefs.
- `hx` (configured git editor) panics without a TTY — always `git commit -m "..."`; use `git -c core.editor=true rebase --continue`.