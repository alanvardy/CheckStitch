# Conventions

Shared factual appendix for Design/Structure/Plan. All paths repo-relative. Core sources under `CheckStitchCore/Sources/CheckStitchCore/`.

## Canonical commands
- **Gate**: `bash scripts/test.sh` → `make build` (simulator) → pre-boot this worktree's `.simulator_id` → `make test` → `make build-mac` → `make watch-build` → `make widget-build` → `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh` → prints `gate: ok`. Single `gate_cleanup` EXIT trap releases lock + shuts down only the resolved UDID.
- **Unit tests (fast)**: `make test-unit` — `xcodebuild -destination MAC_SIM CODE_SIGNING_ALLOWED=NO -only-testing:CheckStitchTests test` (macOS host, unsigned, no sim). Preferred for quick iteration.
- **UI smoke**: `make test-ui` — `build-for-testing` then `-only-testing:CheckStitchUITests test-without-building` on a dedicated simulator (never a bare `name=` destination).
- **Localization**: `bash scripts/l10n-check.sh` (Python mirror of the six-language/required-key/differs checks) — run **before** adding keys.
- Other targets: `make build` (:25), `make build-mac` (:38), `make build-mac-signed` (:48, needs `-allowProvisioningUpdates`), `make watch-build` (:58), `make widget-build` (:67). `bash scripts/run-devices.sh` (device; `RUN_WATCH=0` skips watch), `bash scripts/run-watch.sh`.
- **Test gate**: `make test` = `test-unit` + `test-ui` (`Makefile:77`).
- Warnings-as-errors are enforced in `CheckStitch.xcodeproj/project.pbxproj` (Debug + Release); `CheckStitchCore` local SPM package is not separately enforced. `scripts/tests/run.sh` pins per-leg coverage (`warnings_as_errors_reaches_compiling_legs`).

## Test-suite inventory
- `CheckStitchTests/` — unit suites; Swift Testing (`@Test`, `#expect`, `@testable import CheckStitchCore`) unless noted. Test targets do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with `@MainActor` per suite.
- `CheckStitchUITests/CheckStitchUITests.swift` — one XCTest smoke (`runsForEachTargetApplicationUIConfiguration` false; `testLaunchAndAccessibilitySmoke`).

| Suite | File | Covers | Platform/Gating |
| --- | --- | --- | --- |
| Store | `ChecklistStoreTests.swift` | create/rename/delete/move/unique-name/freshCopy | XCTest, macOS |
| Store | `WatchChecklistStoreTests.swift` | watch store | `@MainActor` |
| Store | `WidgetRunStateStoreTests.swift` | widget run state | `@MainActor` |
| Codec | `ChecklistCodecTests.swift` | round-trip, version classify | XCTest, `@MainActor` |
| Merge | `ChecklistMergeTests.swift` | LWW, tombstones, order, convergence (~1000 lines) | `@MainActor` |
| Widget | `ChecklistWidgetDisplayModelTests.swift` | display model, `hasChecklists` | Swift Testing |
| Query | `ChecklistEntityQueryTests.swift` | entities/matching/suggested | Swift Testing, `@MainActor` |
| Intents | `RunChecklistIntentTests.swift`, `ListChecklistsIntentTests.swift` | run/list refusal | `@MainActor` |
| Localization | `LocalizationTests.swift`, `LocalizedStringResolutionTests.swift`, + `LocalizationFixtures.swift`, `LocalizationTestHelpers.swift` | six-language, required keys, embedded bundle | macOS |
| Grouping/mutation | `ChecklistGroupingTests.swift`, `ChecklistListViewModelTests.swift` | isLoose/sections/visible*, list VM | macOS |
| Sync | `ChecklistSyncCoordinatorTests.swift`, `ChecklistSyncingContractTests.swift`, `ChecklistSyncServiceTests.swift`, `UbiquitousChecklistSyncTests.swift`, `ChecklistSyncDiagnosticsTests.swift`, `ChecklistSyncMessageTests.swift` | sync service/merge adoption | macOS |
| Import/export | `ChecklistImportSessionTests.swift`, `ChecklistImportExportViewModelTests.swift`, `ChecklistExportTests.swift` (XCTest) | import insert/replace, export selection | macOS |
| `#if os(macOS)` | ViewRenderTests:27, ColorCrossPlatformTests:5,15, ChecklistDetailViewTests:72,164,179,238,260,276,311, InterfaceSettingsViewTests:12,29,37, AboutViewTests:23, MacWindowFrameTests:1, ExportChecklistsViewTests:36, PurchaseSettingsViewTests:66 | macOS-only view/render tests | `#if os(macOS)` |
| Canary | `SmokeTests.swift` (`@testable import CheckStitchCore`, Swift Testing), `HarnessTests.swift` | harness canary | macOS |

- Fakes/helpers: `CheckStitchTests/TestFixtures.swift` (many `@MainActor` helpers), `StubBundle.swift`.
- `LocalizationFixtures.swift`: `guardedCatalogs = ["App","Core","Watch","Widget"]` (:10); `requiredKeys` per catalog (:12-169) — **a new key must be added**; `infoPlistTargets` (:50-58); `excludedIdentities` (:60-79); `missingInfoPlistKeys(in:, required:)` (:84-90).

## Localization workflow for a new string
1. Add the key object to the owning `.xcstrings` with all 6 non-empty `stringUnit.value` entries (`en, de, es, fr, ja, zh-Hans`), typically `extractionState: "manual"` (precedent `"%lld days ago"` at `CheckStitch/Localizable.xcstrings:537-576`; pluralized style `"%lld ..."` reads "1 items" for one, per repo precedent — no plural variants).
2. Add the key to the matching catalog array in `LocalizationFixtures.requiredKeys`.
3. If a non-English value may legally equal English, add an `ExclusionEntry` to `excludedIdentities`.
4. If the key is an `InfoPlist.strings` target, ensure it's in `infoPlistTargets` keys and non-empty in each `<lang>.lproj/InfoPlist.strings`.
5. Run `bash scripts/l10n-check.sh`, then `make test-unit`.

## User-facing string locations
- App strings live in `CheckStitch/Localizable.xcstrings`; Core in `CheckStitchCore/Sources/CheckStitchCore/Resources/Localizable.xcstrings`; Watch in `CheckStitchWatch/Localizable.xcstrings`; Widget in `CheckStitchWidget/Localizable.xcstrings`.
- `.lproj` dirs hold only `InfoPlist.strings`. `GENERATE_INFOPLIST_FILE = YES` — Reminders usage-description keys are required (Reference: `/Users/vardy/dev/SingleThread` `NSReminders*UsageDescription` keys).
- Six languages: `en, de, es, fr, ja, zh-Hans` (`LocalizationTestHelpers.swift:57-58`).

## Build/verify gotchas
- Never leave a bare `name=` destination in any script — it selects a shared device and wedges parallel agents. Explicit `SIM=` > worktree `.simulator_id` > shared default (Makefile).
- `make build-mac-signed`, `run-watch.sh`, `run-devices.sh` are device helpers **outside** the enforced gate set. `make build-mac` (unsigned) is the gate's platform leg.
- Test targets must not add `SWIFT_DEFAULT_ACTOR_ISOLATION`; use `@MainActor` per-suite.
- Simulator windows: gate takes a bounded host lock (`${TMPDIR:-/tmp}/checkstitch-simulator.lock`, `LOCK_TIMEOUT` default 60s); a stale lock whose PID is dead is reaped; shutdown is scoped to the resolved UDID only (never `all`/`booted`).
- `CheckStitchCore` package: iOS 18.7 / macOS 27.0 / watchOS 26.0 (`CheckStitchCore/Package.swift:6-10`); built into iOS (`make build`), macOS (`build-mac`), watchOS (`watch-build`), widget (`widget-build`) slices of the gate.
- If no test target matched in a slice, say so in the completion artifact and treat the build as the gate.