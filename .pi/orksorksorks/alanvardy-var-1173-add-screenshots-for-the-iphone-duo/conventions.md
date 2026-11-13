# Conventions

Shared factual appendix for Design/Structure/Plan. Commands and file:line references
from the current checkout.

## Canonical commands
- **Gate**: `./scripts/test.sh` — `make build` (simulator) → headless pre-boot of this
  worktree's simulator → `make test` → `make build-mac` → `make watch-build` →
  `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`; prints
  `gate: ok`. Not part of the gate: `make appstore-screenshots`
  (`scripts/appstore-screenshots.sh`), `run-devices.sh`, `run-watch.sh`.
- **Fast unit leg**: `make test-unit` — `CheckStitchTests` on `platform=macOS`,
  `CODE_SIGNING_ALLOWED=NO` (`Makefile:81-90`).
- **UI leg**: `make test-ui` — `CheckStitchUITests` via build-for-testing →
  test-without-building on `.simulator_id` (`Makefile:92-101`).
- **Builds**: `make build` (simulator), `make build-mac` (unsigned macOS, gate only),
  `make build-mac-signed` (development team, for running), `make watch-build`.
- **Screenshot capture**: `make appstore-screenshots` → `bash scripts/appstore-screenshots.sh`
  (`Makefile:110-111`); `bash scripts/appstore-screenshots.sh --help` prints the header
  doc; `bash scripts/appstore-screenshots.sh [class ...]`.
- **Shell tests**: `bash scripts/tests/run.sh` (stubs `xcrun`/`xcodebuild`/`sips`/etc.).
- **Script syntax/lint**: `/bin/bash -n <script>` (bash 3.2; pinned by
  `scripts_parse_under_system_bash`, `scripts/tests/run.sh:795-807`);
  `shellcheck scripts/*.sh scripts/tests/*.sh` (gate only).
- **Localization**: `bash scripts/l10n-check.sh` before adding user-facing strings.

## Test-suite inventory

### `scripts/tests/run.sh` (single shell suite, run by the gate)
- Harness: `new_stubs()` (`:18-32`), `run_case()` (`:34-43`), `PASS`/`FAIL` tally and
  non-zero exit on any failure (`:580-581`).
- appstore stubs: `stub_appstore_capture` (`:575-608`), `stub_appstore_watch_capture`
  (`:703-737`); fake `simctl list` inventory, `get_app_container`, `simctl io`, and a
  path-aware `sips`.
- appstore cases: boot/install/launch (`:610-617`), size mismatch names file (`:619-627`),
  wallpaper staging (`:629-637`), seeded-main→empty ordering (`:639-652`), five-shot
  sequence + appearance (`:654-686`), six language dirs (`:688-701`), watch install/launch
  (`:738-755`), per-run manifest keys (`:739-754`), CLI help/unknown flag/class/language
  exit 2 (`:756-780`), preflight mismatch (`:782-788`), system-bash parseability
  (`:795-807`).
- Other suites in the same file: resolve-sim-udid (`:45-93`), gate/simulator lock
  (`:96-176`), run-simulator/run-watch (`:178-318`), run-devices (`:320-462`), macOS
  network entitlement (`:464-491`), warnings-as-errors (`:493-546`), document-type
  registration (`:548-559`), shared-width gutter (`:561-571`).

### `CheckStitchTests/` (Swift Testing, macOS-hosted)
- `LaunchSeamsTests.swift` — arg/env parsing, `--ui-testing*` flags, non-int index,
  unknown language tolerated→nil, seed env→URL, seed envelope happy/malformed/missing.
- `DuoDisplayTests.swift` — `isOuterPortrait` machine × size-class matrix, malformed
  ids fail safe.
- `ChecklistLayoutTests.swift` — standard vs Duo-outer inset/width, stride domain,
  425 pt crossover, safe-area case. Companion `ChecklistWidthTests.swift`.
- `OrientationPreferenceTests.swift` — default enabled, round-trip, non-Bool fallback,
  `OrientationPolicy` mapping; `@MainActor`; iOS-only `mask` exercised manually (`:35-36`).
- `SettingsBindingsTests.swift` / `SettingsViewModelTests.swift` — settings bag
  snapshot/writeback incl. `allowsLandscape`.
- `TestFixtures.swift` — `makeIsolatedDefaults()` (`:12-17`), `makeItem`,
  `sharedTestEventStore`, spies (`SpyReminderCreator`, `SpyReminderDestination`),
  `InMemoryChecklistSync`.

### `CheckStitchUITests/CheckStitchUITests.swift` (one XCTest class)
- `testLaunchAndAccessibilitySmoke` (`:12-35`), `testUITestingSeededListRendersARow`
  (`:37-45`), `testUITestingOpenSettingsShowsSettingsSheet` (`:47-55`),
  `testUITestingOpenChecklistPushesDetail` (`:57-62`); per-test seed fixture
  `writeSeedFixture()` (`:64-74`). `@MainActor` per test.

## Conventions / gotchas
- These are the launcher seams the screenshot script drives: `LaunchSeams` is the sole
  `ProcessInfo` reader (`CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift:7`);
  views never read launch args.
- Appearance is simulator-level (`xcrun simctl ui … appearance`), not a launch seam
  (`scripts/appstore-screenshots.sh:318-325`).
- Language is primed by `--ui-testing-app-language` and persisted via
  `AppLanguagePreference` key `"appLanguage"` (`UserDefaults.standard`).
- Wallpaper slot = `<class>-<screen>`; the app consumes a single
  `background.jpg`/`background.json` pair, no class notion
  (`CheckStitch/BackgroundImageStore.swift:83-90`, `:189-193`).
- New device class ⇒ `DEVICE_TYPES` + `size_for` + `device_name_for` + class whitelist
  + header doc + `<class>-<screen>` fixtures/manifest
  (`scripts/appstore-screenshots.sh:82`, `:85-98`, `:374-380`).
- Script must parse under macOS `/bin/bash` 3.2: no associative arrays; no here-doc
  inside `$(…)`; shellcheck does not catch 3.2-only rejections.
- Test targets deliberately do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in
  with `@MainActor` (`Makefile:80`).
- Warnings-as-errors are enforced at project level (Debug/Release) for Xcode builds;
  `CheckStitchCore` SPM is not separately enforced.
- Destination precedence: explicit `SIM=` > this worktree's `.simulator_id`
  (`82AA75FA-FC5B-4860-81AB-CF198E8CBAE4`) > shared default. Never a bare `name=`
  destination outside the screenshot script's name→UDID resolution.
