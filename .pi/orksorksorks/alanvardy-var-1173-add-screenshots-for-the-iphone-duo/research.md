# Research Findings

Scope: current checkout of `alanvardy-var-1173-add-screenshots-for-the-iphone-duo`
(CheckStitch). All `file:line` references are from this working tree unless noted.

## Q1: How does `scripts/appstore-screenshots.sh` work end to end?

### Findings
- Entry point `make appstore-screenshots` → `bash scripts/appstore-screenshots.sh $(ARGS)`
  (`Makefile:110-111`); explicitly **not** part of the gate (`AGENTS.md:83`).
- Script is `set -euo pipefail`, `cd "$(dirname "$0")/.."`, 415 lines total.
  Header/usage `:1-30`, printed by `--help` via `sed -n '2,30p' "$0"` (`:75`).
- Constants `:34-50`: `BUNDLE=app.alanvardy.CheckStitch`, `SCHEME=CheckStitch`,
  `DD=build/appstore-dd`, `APP=$DD/Build/Products/Debug-iphonesimulator/CheckStitch.app`,
  `OUT=build/appstore-screenshots`, `SEED_FILE=$PWD/scripts/fixtures/appstore-seed.json`.
- Watch leg `:41-46`: `WATCH_SCHEME=CheckStitchWatch`, `WATCH_CLASS=watch-46mm`,
  `WATCH_PATTERN='Apple Watch Series 11 \(46mm\)'`, `WATCH_SCREENS=("1-list" "2-detail")`.
- `LANGUAGES=(en de es fr ja zh-Hans)` (`:62`). CLI parse loop `:64-79`:
  `--fetch-wallpapers`, `--refetch-wallpapers`, `--wallpaper-url`, `--wallpaper-dir`,
  `--no-build`, `--no-install`, `--settle`, `--lang`, `--udid <class>=<udid>`,
  `-h/--help`, unknown `-*` exits 2, positional args append to `CLASSES`.
- Device classes `DEVICE_TYPES=( "iphone-6.3:iPhone 17$" "ipad-13:iPad Pro 13-inch \\(M5\\)" )`
  (`:82`) — `<label>:<simctl name regex>`, newest runtime wins. No associative arrays
  (bash 3.2 constraint, `:84`).
- `size_for()` (`:85-91`): `iphone-6.3`→`1206x2622`, `ipad-13`→`2064x2752`,
  `watch-46mm`→`416x496`. `device_name_for()` (`:93-98`) maps label→manifest device name.
  Class whitelist `:374-380`, language whitelist `:382-387` (both exit 2 on unknown).
- Screen slots `:106-112`: `SCREENS=( "main-dark:1-main-dark" "empty:2-empty"
  "settings:3-settings" "main-light:4-main-light" "detail:5-detail" )`, i.e.
  `<wallpaper-slot>:<output-stem>`.
- Per-stem appearance + launch args inside `capture_class` (`:326-341`): `*-dark` →
  `simctl ui "$UDID" appearance dark`, `*-light` → `light` (`:318-325`). Stems launch
  `1-main-dark`/`4-main-light` with `--ui-testing --ui-testing-app-language <lang>`;
  `2-empty` adds `--ui-testing-empty`; `3-settings` adds `--ui-testing-open-settings`;
  `5-detail` adds `--ui-testing-open-checklist 0`.
- `shoot()` (`:268-277`): terminate, sleep 1, then
  `SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE" simctl launch
  --terminate-running-process "$UDID" "$BUNDLE" "$@"`, sleep `$SETTLE` (default 6),
  `simctl io ... screenshot --mask ignored "$out"`.
- `resolve_udid()` (`:246-259`) parses `simctl list devices available --json` in Python
  and picks the newest matching runtime. `boot_and_install()` (`:261-266`). Omitted.
- Verification: `preflight_size()` (`:287-296`) screenshots a temp PNG and checks it
  equals `size_for`; `verify_size()` (`:279-285`) does the same post-shot and returns 1
  with `!! <file> is <dims>, expected <size>`.
- Output tree `build/appstore-screenshots/<lang>/<device>/<n>-<name>.png` +
  per-run `manifest.json` (`:7-10`, `:316-341`). `write_manifest()` (`:298-307`) writes
  `{class,device,udid,size,screens}` via inline Python.
- `capture_watch()` (`:354-370`) mirrors the loop with `watch_shot()` (`:343-352`),
  no `--terminate-running-process`, no wallpaper staging.
- Dispatch `:396-414`: fetch wallpapers if requested, build iOS/watch via `xcodebuild`
  generic platform destination, loop `DEVICE_TYPES` and the watch class, print
  `==> done: $OUT`. Default class if none passed is `iphone-6.3` (`:372`).
- A new device class touches: `DEVICE_TYPES` (`:82`), `size_for` (`:85-91`),
  `device_name_for` (`:93-98`), class whitelist (`:374-380`), header comment, plus
  matching `<class>-<screen>` wallpaper slots.

## Q2: What launch-argument / persisted-defaults seams prime app state?

### Findings
- `LaunchSeams` is the **only** reader of `ProcessInfo`/launch args in the app
  (`CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift:7`). `struct LaunchSeams:
  Sendable, Equatable` (`:9`); fields `:10-15`: `isUITesting`, `isEmpty`, `seedURL: URL?`,
  `openSettings`, `openChecklistIndex: Int?`, `language: AppLanguage?`; defaults all off
  (`:17-27`). Ephemeral suite `uiTestingSuiteName = "app.alanvardy.CheckStitch.uitesting"`
  (`:31`). Pure `parse(arguments:environment:)` (`:35-66`) — every flag forces
  `isUITesting = true`:
  - `--ui-testing` (`:39`), `--ui-testing-empty` (`:41`), `--ui-testing-open-settings` (`:43`)
  - `--ui-testing-open-checklist <int>` (`:45-49`, non-int → nil but advances index)
  - `--ui-testing-app-language <raw>` (`:51-55`, unknown → nil)
  - env `CHECKSTITCH_UITEST_SEED` non-empty → `isUITesting`, `seedURL` (`:61-64`)
  - unknown flags tolerated (`:58-59`)
- `current(processInfo:)` (`:68-70`); `loadSeedEnvelope()` (`:73-80`) decodes via
  `ChecklistCodec.classify`.
- Consumption `CheckStitch/MyApp.swift`: `LaunchSeams.current()` (`:37`); when
  `isUITesting`, a `UserDefaults(suiteName: uiTestingSuiteName)` is wiped and used instead
  of the App Group (`:53-60`); `ChecklistStore(defaults:seed:)` (`:62`); language priming
  `AppLocaleState.current.set(language)` (`:63`); `ContentView(seams:)` (`:82`,`:116`).
  Sync/purchase/crash reporting all gated on `!isUITesting` (`:41`, etc.).
- `CheckStitch/ContentView.swift`: `var seams = LaunchSeams()` (`:7`); `.task` opens
  settings or pushes the checklist at `openChecklistIndex` (`:188-195`).
- Language persistence is **outside** `LaunchSeams`: `AppLocaleState` (`@MainActor
  @Observable`, `:16`,`:31-34`) writes `AppLanguagePreference` key `"appLanguage"`
  (`AppLanguagePreference.swift:11`, `UserDefaults.standard`); `AppLanguage` cases
  `system/en/de/es/fr/ja/zh-Hans` (`AppLanguage.swift:5`).
- Appearance is **not** a launch arg: `@AppStorage("appearanceMode")` in
  `ContentView.swift:20-21`; `AppearanceMode` enum (`AppearanceMode.swift:16`),
  applied by `AppDelegate` (`:29`).
- Script usage: seed env in `shoot()` (`:270-273`), per-stem args (`:330-334`),
  language `--ui-testing-app-language` (`:326-339`), simulator-level appearance
  (`:324-325`). Watch app reads the same seams (`CheckStitchWatch/CheckStitchWatchApp.swift:6,10`).

## Q3: Where does the app detect the Duo outer display and adjust layout?

### Findings
- Detection is pure/cross-platform: `CheckStitchCore/Sources/CheckStitchCore/DuoDisplay.swift`
  — `outerPortraitMachines: Set<String> = ["iPhone19,4"]` (`:8`); `isOuterPortrait(
  machine:isCompactWidth:isRegularHeight:)` (`:13-19`) returns true only when the machine
  is known **and** width compact **and** height regular. The size-class pair is what scopes
  the match — the inner display and outer landscape both fail it (`:11-12`).
- Platform binding iOS-only: `CheckStitch/DuoOuterPortrait.swift` — `machineIdentifier`
  reads `hw.machine` via `uname` (`:14-25`); returns `""` on macOS and the Simulator
  (`:23-24`). `context(horizontal:vertical:machine:)` (`:27-36`) maps size classes into
  `ChecklistLayout.Context(isDuoOuterPortrait:)`.
- Layout policy pure: `CheckStitchCore/Sources/CheckStitchCore/ChecklistLayout.swift` —
  `Context` (`:14-25`, `.standard` false at `:24`); `horizontalInset` 16 on Duo outer vs
  32 default (`:28-34`); `maxContentWidth` Duo path `min(340, viewportWidth * 0.8)` vs
  default `min(340, 0.6W)` (`:43-56`); crossover at viewport 425.
- Consumption: `CheckStitch/ContentView.swift:17-18` size-class env; `layoutContext`
  (`:460-462`); applied at `:503-505`, `:521-533`, `:759`.
- Non-Duo fails safe: unknown/empty/malformed machine, macOS, watchOS, Simulator all
  resolve `isDuoOuterPortrait = false` → `.standard`
  (`DuoOuterPortrait.swift:23-24`, `ChecklistLayout.swift:24,33-34,53-55`).
- **No inner-panel, pose (`folded`/`book`/`open`), hinge, or Duo-landscape code exists.**
  Only doc words in `DuoDisplay.swift:11-12` and unrelated "folded" comments in
  `ChecklistStore.swift:137,749`. The inner display is excluded implicitly by the
  size-class test; Duo outer landscape (compact height) falls back to `.standard`.
- General orientation machinery is separate (Q4). Tests:
  `CheckStitchTests/DuoDisplayTests.swift`, `CheckStitchTests/ChecklistLayoutTests.swift`.

## Q4: How does the iOS app declare and control interface orientation?

### Findings
- `CheckStitch/Info.plist` has **no** orientation keys; orientations come from generated
  build settings (`GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_FILE = CheckStitch/Info.plist`,
  `project.pbxproj:614-615`, `:660-661`):
  - iPhone: `Portrait LandscapeLeft LandscapeRight` (`pbxproj:626-627`, `:672-673`)
  - iPad: all four incl. upside-down (`pbxproj:627`, `:673`)
  - `TARGETED_DEVICE_FAMILY = "1,2"` (`pbxproj:649`, `:689`).
  These advertise the maximum; the runtime delegate mask overrides them.
- Preference persisted: `CheckStitch/OrientationPreference.swift:25`
  `defaultsKey = "allowsLandscape"`, `UserDefaults.standard` (`:13-15`); absent key
  resolves to `true` (`:28-30`); `setLandscapeEnabled` (`:32-34`).
  UI mirror `ContentView.swift:26` `@AppStorage("allowsLandscape")`.
- Policy: `OrientationPreference.swift:48-55` `enum OrientationPolicy { portrait,
  allButUpsideDown }`, `init(allowsLandscape:)`; iOS-only `mask` (`:58-67`) maps to
  `UIInterfaceOrientationMask`.
- Delegate: `CheckStitch/AppDelegate.swift:53-59`
  `application(_:supportedInterfaceOrientationsFor:)` returns the policy mask.
  `applyLock(allowsLandscape:)` (`:38-51`) resolves the active `UIWindowScene`, calls
  `setNeedsUpdateOfSupportedInterfaceOrientations()` (`:46`) and
  `scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))` (`:48-50`),
  logging via `Logger` (subsystem `app.alanvardy.CheckStitch`, category `Orientation`,
  `:12-13`).
- Toggle flow: `InterfaceSettingsView.swift:52-65` (`accessibilityIdentifier("allowLandscapeToggle")`)
  → `SettingsView.swift:33` → `ContentView.swift:113-115` `.onChange` →
  `AppearanceViewModel.swift:17-21` `allowsLandscapeChanged` → `AppDelegate.applyLock`.
- Tests: `CheckStitchTests/OrientationPreferenceTests.swift` (default/round-trip/
  non-Bool/policy mapping); the iOS-only `mask` conversion is exercised manually
  (`:35-36`). `SettingsBindingsTests`/`SettingsViewModelTests` cover the round-trip.
- **No launch seam primes orientation**: `LaunchSeams` has no orientation field.

## Q5: How are wallpaper slots/manifest defined, fetched, staged, referenced?

### Findings
- Fixture dir `scripts/fixtures/appstore-wallpapers/` holds `manifest.json`, `README.md`,
  and 10 committed JPEGs: `iphone-6.3-{main-dark,empty,settings,main-light,detail}.jpg`
  and the same five `ipad-13-*.jpg`. No watch slots.
- Slot = `<class>-<screen>` (class + `SCREENS` stem, `appstore-screenshots.sh:106-112`);
  keyed per class, not per language. `slot_names()` emits every class×screen
  (`:129-137`).
- Manifest schema: object keyed by slot → `{file, source, photographer,
  photographerURL, fetchedAt}` (UTC ISO-8601). Written by `fetch_wallpapers` inline
  Python with `json.dump(..., indent=2, sort_keys=True)` (`:145-219`).
- Fetch flags `:66-69`; API default `WALLPAPER_API=https://vardy.cc/unsplash/random`
  (`:103`), dir `IOS_WALLPAPER_DIR` (`:101`), `MANIFEST` (`:102`). One photo/slot, kept
  unless `--refetch-wallpapers`; SHA-256 dedupe up to `REDRAWS=5` (`:156-198`).
  `--wallpaper-url slot=url` / `*=url` pins draws (`:153-155`, `:187-190`).
- Staging `stage_slot()` (`:226-244`): resolves `wallpaper_dir()` =
  `simctl get_app_container "$UDID" "$BUNDLE" data` + `/Library/Application Support/CheckStitch`
  (`:120-127`), copies the JPEG to `background.jpg` and writes `background.json`
  `{photographer, fetchedAt, photographerURL?}`; exit 3 (missing slot) / 4 (missing
  source). Called per class/screen before each shot (`:322-329`).
- App side reads the same files: `CheckStitch/BackgroundImageStore.swift:189-193`
  (`defaultDirectory`), `:83-90` (`background.jpg`/`background.json`),
  `:98-110` (load/refresh). The app has no class notion — the class dimension lives
  entirely in script/fixtures. Per-run output manifest is separate
  (`write_manifest`, `:298-307`).

## Q6: What shell-script test infrastructure exists, and what covers the script?

### Findings
- Single file `scripts/tests/run.sh` (`#!/bin/bash`, `set -euo pipefail`, `cd` to repo
  root, `PASS`/`FAIL` counters — `:1-9`). Helpers: `cleanup`/`trap` (`:11-14`),
  `new_stubs()` writing per-tool stub executables into a temp dir on `PATH` (`:18-32`),
  `run_case()` (`:34-43`), final tally + non-zero on failure (`:580-581`).
- Stubbed tools for appstore cases: `xcrun`, `xcodebuild`, `sips` (plus `defaults`,
  `make`, `open`, `osascript` elsewhere).
- `stub_appstore_capture` (`:575-608`): custom `xcrun` serves `simctl list` JSON
  (`iPhone 17` / `IPHONE-UDID-1`), `get_app_container` → `$STUB_ROOT/container`,
  `simctl io` writes the screenshot file; path-aware `sips` reports `1206x2622` for
  `appstore-preflight` and the caller-supplied mismatch otherwise.
  `stub_appstore_watch_capture` (`:703-737`) adds a watchOS runtime → `WATCH-UDID-1`,
  `sips` `416x496`.
- Cases: boot/install/launch (`:610-617`), size mismatch exits 1 and names the file
  (`:619-627`), wallpaper staging (`:629-637`), seeded-main-then-empty ordering
  (`:639-652`), five-shot sequence + appearance (`:654-686`), six language dirs
  (`:688-701`), watch install/launch (`:738-755`), per-run manifest keys
  (`:739-754`), help/unknown-flag/unknown-class/unknown-language exit 2 (`:756-780`),
  preflight mismatch (`:782-788`).
- Bash-version constraint: `scripts_parse_under_system_bash` (`:795-807`) runs
  `/bin/bash -n` (macOS 3.2) over `scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh`;
  shellcheck does not catch 3.2-only rejections. Shellcheck itself runs in the gate
  (`AGENTS.md:79`), not inside `run.sh`.
- All appstore cases run the real script with stubbed tools; assertions read
  `xcrun.log` and real files under `build/appstore-screenshots/`.

## Q7: How are unit tests structured for these seams?

### Findings
- Two test targets: `CheckStitchTests/` (Swift Testing, macOS-hosted, `make test-unit`,
  `CODE_SIGNING_ALLOWED=NO`, no sim/signing — `Makefile:81-90`) and
  `CheckStitchUITests/` (one XCTest class — `Makefile:92-101`).
- One suite per SUT, `struct <Thing>Tests`: `LaunchSeamsTests.swift`,
  `DuoDisplayTests.swift`, `ChecklistLayoutTests.swift`, `OrientationPreferenceTests.swift`.
  Core SUTs imported via `@testable import CheckStitchCore`; app-target SUTs via
  `@testable import CheckStitch`.
- `@Test` functions behaviour-named (no `test` prefix, e.g. `noArgumentsIsANoOp`,
  `LaunchSeamsTests.swift:5-8`); `@Test(arguments:)` tables for matrices (languages
  `LaunchSeamsTests.swift:29`; size classes `DuoDisplayTests.swift:38`; malformed
  machines `:50`; layout stride `ChecklistLayoutTests.swift:22`); `#expect(...)`.
- Test targets do **not** set `SWIFT_DEFAULT_ACTOR_ISOLATION`; suites opt in with
  `@MainActor` (`Makefile:80`). `OrientationPreferenceTests` is `@MainActor`
  (`:5-6`); the LaunchSeams/Duo/Layout suites are not.
- Shared fixtures `CheckStitchTests/TestFixtures.swift`: `makeIsolatedDefaults()`
  (`:12-17`), `makeItem`, `sharedTestEventStore`, spies, `InMemoryChecklistSync`.
  LaunchSeams seed tests instead write temp files with `FileManager` + `UUID` and
  `defer`-remove (`LaunchSeamsTests.swift:52-90`).
- Seam coverage: `LaunchSeamsTests` parses every `--ui-testing*` flag, non-int index,
  unknown language, unknown flag, seed env → URL, seed envelope happy/malformed/missing.
  `DuoDisplayTests` machine×size-class matrix incl. fail-safe malformed ids.
  `ChecklistLayoutTests` inset/width math incl. Duo outer and the 425 pt crossover.
  `OrientationPreferenceTests` default/round-trip/non-Bool/policy.
- UI seam: `CheckStitchUITests/CheckStitchUITests.swift` (XCTest, `@MainActor` per
  test): launch/accessibility smoke (`:12-35`), seeded list row (`:37-45`), open
  settings (`:47-55`), open checklist detail (`:57-62`). Seed fixture written per test
  (`:64-74`, a `{"version":6,...}` envelope).

## Cross-Cutting Observations
- **Layering convention**: pure, cross-platform logic lives in `CheckStitchCore`
  (`DuoDisplay`, `ChecklistLayout`, `LaunchSeams`) and is unit-tested on macOS; platform
  bindings (`DuoOuterPortrait`, `AppDelegate`, `OrientationPreference`) live in the app
  target and are gated with `#if os(iOS)`.
- **Single-seam rule**: `LaunchSeams` is the only launch-arg reader; views never read
  `ProcessInfo`. Any new automated-run knob belongs there.
- **Fail-safe default**: unknown Duo machine/size class resolves to `.standard` layout;
  `OrientationPreference` absent key resolves to landscape-enabled.
- **Script/fixture coupling**: a new device class requires coordinated edits in
  `DEVICE_TYPES`, `size_for`, `device_name_for`, the class whitelist, the header doc,
  and the `<class>-<screen>` wallpaper slots + manifest. The app itself has no class
  notion.
- **bash 3.2**: the screenshot script must parse under `/bin/bash -n` (no associative
  arrays); the gate pins this.
- **Reference implementation exists**: `/Users/vardy/dev/SingleThread`
  (`alanvardy-var-1172-add-screenshots-for-the-iphone-duo`, `done.md`) already added a
  `DuoOuterPortraitTests`, `LaunchArgument.orientation`, `AppDelegate.supportedOrientations`,
  `--duo-pose`, and Duo capture functions; its `done.md` records the latent bugs found
  (Reminders TCC pre-grant; landscape geometry needing the delegate mask to advertise
  landscape). This repo has none of that yet.

## Open Areas
- No runtime/window-level code forces a Duo display role or hinge pose in this repo;
  pose selection is not modelled anywhere (Q3).
- No launch seam primes orientation or Duo context; `LaunchSeams` has no orientation
  field (Q2, Q4).
- The iOS-only `OrientationPolicy.mask` conversion has no unit test (Q7).
- Whether `--duo-pose`/inner-panel capture is achievable headlessly is not answerable
  from this codebase; `done.md` says the hinge pose must be set in Device Hub before
  each run and that inner capture needs a separate invocation.
