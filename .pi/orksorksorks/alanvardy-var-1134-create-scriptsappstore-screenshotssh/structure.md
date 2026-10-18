# Structure Outline

## Approach

Grow CheckStitch a single hermetic launch seam (`LaunchSeams` in `CheckStitchCore`)
that `MyApp.init()` reads, and build `scripts/appstore-screenshots.sh` around it
one screen at a time. The script owns device resolution, build/boot/install,
wallpaper staging and `sips` verification; each slice lands end to end (real
simulator → real PNG) with its Swift and shell tests green, so the tree is always
demoable and the riskiest integration (app-container wallpaper staging) is
front-loaded.

---

## Phase 1: Walking skeleton — one hermetic empty-state capture

`scripts/appstore-screenshots.sh` resolves the iPhone 17 simulator, builds,
boots, installs, launches with `--ui-testing --ui-testing-empty`, and writes a
real `build/appstore-screenshots/en/iphone-6.3/1-main-dark.png` that `sips`
confirms is 1206×2622. The app launches into the empty state on an ephemeral
`UserDefaults` suite, with Sentry/purchase/KVS/WCSession/background-fetch off, so
the simulator's real App Group container is untouched.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift` (new),
`CheckStitch/MyApp.swift`, `scripts/appstore-screenshots.sh` (new),
`scripts/tests/run.sh`, `CheckStitchTests/LaunchSeamsTests.swift` (new)

**Key changes**:
- `public struct LaunchSeams: Sendable, Equatable` — fields `isUITesting`,
  `isEmpty`, `seedURL`, `openSettings`, `openChecklistIndex`, `language`; parsed
  from `--ui-testing`, `--ui-testing-empty`,
  `--ui-testing-open-settings`, `--ui-testing-open-checklist <n>`,
  `--ui-testing-app-language <id>` and env `CHECKSTITCH_UITEST_SEED`
- `static func parse(arguments:environment:) -> LaunchSeams` and
  `static func current(processInfo:) -> LaunchSeams` — new
- `MyApp.init()` branches on `LaunchSeams.current`: ephemeral suite +
  suppressed services when `isUITesting`
- script helpers `resolve_udid`, `boot_and_install`, `shoot`, `verify_size`,
  `-h`/unknown-flag handling — new

**Contract**: `LaunchSeams` is the only arg/env reader (views never call
`ProcessInfo`); `parse` is pure and fully unit-testable. Ephemeral suite name
`app.alanvardy.CheckStitch.uitesting`. Script CLI: `[options] [class ...]`,
classes default to all (only `iphone-6.3` wired here), unknown `-*` exits 2.

**Tests**: `LaunchSeamsTests` (parse matrix: each flag, env seed URL, unknown
flag tolerated, `--ui-testing` without seed → empty) + `CheckStitchUITests`
`--ui-testing-empty` launch asserts `emptyStateCreateButton` exists; harness
`run_case` stubs `xcrun`/`sips` and asserts boot/install/launch argv + a
size-mismatch case exits 1 naming the file.
**Verify**: `make test-unit` + `bash scripts/tests/run.sh`; manual
`make build && bash scripts/appstore-screenshots.sh iphone-6.3 --no-build`→ PNG.

---

## Phase 2: Deterministic wallpapers staged into the app container

Every iOS capture gets its `<class>-<screen>` fixture wallpaper (and
`background.json` credit) copied into the app's data container before launch, so
shots are byte-identical across reruns and machines.

**Files**: `scripts/appstore-screenshots.sh`,
`scripts/fixtures/appstore-wallpapers/` (10 JPEGs + `manifest.json`, remapped),
`CheckStitch/BackgroundImageStore.swift` (read-only confirmation)

**Key changes**:
- `stage_slot <class> <screen> <udid>` — resolves `simctl get_app_container`,
  writes `…/Library/Application Support/CheckStitch/background.jpg` +
  `background.json` from the manifest entry
- `--fetch-wallpapers`, `--refetch-wallpapers`, `--wallpaper-url`,
  `--wallpaper-dir` — new options

**Contract**: slot keys `<class>-main-dark|empty|settings|main-light|detail`;
container path and `background.json` shape must match what `BackgroundImageStore`
reads at launch (validate against a real container dump before trusting).

**Tests**: harness case stubbing `xcrun simctl get_app_container` + asserting the
staged files and credit fields; `bash -n`/shellcheck clean.
**Verify**: `bash scripts/tests/run.sh`; manual container dump after a run shows
the staged `background.jpg` and the shot visibly uses it.

---

## Phase 3: Seeded main list (dark + light)

`CHECKSTITCH_UITEST_SEED=scripts/fixtures/appstore-seed.json` seeds an in-memory
version-6 envelope so the list renders real checklists; the script captures
`1-main-dark` and `4-main-light` via `simctl ui … appearance`.

**Files**: `CheckStitchCore/.../LaunchSeams.swift`,
`CheckStitchCore/.../ChecklistStore.swift`, `CheckStitch/MyApp.swift`,
`scripts/fixtures/appstore-seed.json` (new), `CheckStitch/ContentView.swift`,
`scripts/appstore-screenshots.sh`, `CheckStitchUITests/CheckStitchUITests.swift`

**Key changes**:
- `ChecklistStore.init(…, seed: ChecklistEnvelope? = nil)` — new parameter; a
  seed replaces the defaults read and forces `canOverwriteStoredPayload = true`
- `MyApp` decodes `LaunchSeams.seedURL` via `ChecklistCodec` and passes the seed
- `.accessibilityIdentifier("checklistRow-\(checklist.id)")` on list rows
- `shoot` gains explicit appearance + `stage_slot` per `SCREENS` entry

**Contract**: the seed file *is* a version-6 `ChecklistEnvelope` produced by
`ChecklistCodec` (no new decode format); `checklistRow-<uuid>` is the UI-test
anchor for the seeded screen.

**Tests**: `LaunchSeamsTests` seed-load case (valid + malformed → nil),
`ChecklistStore` seed-init unit test, UI smoke with seed asserts a
`checklistRow-*` exists; harness asserts the two-shot order.
**Verify**: `make test-unit` + `make test-ui` + `bash scripts/tests/run.sh`.

---

## Phase 4: Settings and detail screens

Adds `--ui-testing-open-settings` and `--ui-testing-open-checklist <n>` wiring so
the script captures `3-settings` and `5-detail`, completing the iOS screen set.

**Files**: `CheckStitchCore/.../LaunchSeams.swift`, `CheckStitch/MyApp.swift`,
`CheckStitch/ContentView.swift`, `CheckStitchCore/.../SettingsViewModel.swift`,
`scripts/appstore-screenshots.sh`, `CheckStitchUITests/CheckStitchUITests.swift`

**Key changes**:
- `MyApp`/`ContentView` apply `openSettings` (`settingsVM.begin(…)`) and
  `openChecklistIndex` (append the nth active checklist UUID to `path`) after
  launch
- `SCREENS` covers all five iOS slots

**Contract**: index is positional over `store.activeChecklists` in list order;
no route enum is introduced (the three existing presentation mechanisms stay).

**Tests**: `LaunchSeamsTests` flag cases; UI tests for the settings sheet and a
pushed detail screen; harness asserts the 5-shot `SCREENS` sequence.
**Verify**: `make test-unit` + `make test-ui` + `bash scripts/tests/run.sh`.

---

## Phase 5: Multi-language loop

`--ui-testing-app-language <id>` sets `AppLocaleState` directly, and the script
loops all six languages writing `<plain-lang>/<device>/…`.

**Files**: `CheckStitchCore/.../LaunchSeams.swift`, `CheckStitch/MyApp.swift`,
`CheckStitchCore/.../AppLocaleState.swift`, `scripts/appstore-screenshots.sh`,
`CheckStitchTests/LaunchSeamsTests.swift`

**Key changes**:
- `LaunchSeams.language` applied to `AppLocaleState` before `ContentView` renders
- script `LANGUAGES=(en de es fr ja zh-Hans)` + language loop and
  `build/appstore-screenshots/<lang>/<device>/` tree

**Contract**: language ids are exactly `AppLanguage` raw values; no new
user-facing strings, so `LocalizationFixtures.requiredKeys` and
`scripts/l10n-check.sh` stay untouched.

**Tests**: `LaunchSeamsTests` language parse (all six + unknown → nil); harness
asserts the six-folder output tree with stubbed `sips`.
**Verify**: `make test-unit` + `bash scripts/tests/run.sh`; manual run shows six
localized folders.

---

## Phase 6: iPad, standalone watch, and per-run manifest

Second and third display classes: iPad 13" via the same iOS path plus a
standalone watch capture (`--ui-testing` on `WatchChecklistWatch`, seeded
in-memory, no `WCSession`), and a `manifest.json` per `lang/device` recording
model, UDID, size pair and screen list.

**Files**: `CheckStitchCore/.../LaunchSeams.swift`,
`CheckStitchCore/.../ChecklistSync.swift` (`WatchChecklistStore`),
`CheckStitchWatch/CheckStitchWatchApp.swift`,
`CheckStitchWatch/WatchChecklistListView.swift`, `scripts/appstore-screenshots.sh`

**Key changes**:
- `LaunchSeams` consumed by `CheckStitchWatchApp`; `WatchChecklistStore.seed(_:)`
  populates `checklists`/`folders` without a transport
- script watch leg (`capture_watch`, `xcrun simctl` watchOS device resolution)
  and `write_manifest <lang> <class>` → `manifest.json`

**Contract**: watch screens `1-list`, `2-detail`; manifest keys
`class, device, udid, size, screens`; watch has no wallpaper slots.

**Tests**: `LaunchSeamsTests` shared by both targets, `WatchChecklistStore`
seed unit test, harness per-class + manifest cases.
**Verify**: `make test-unit` + `make watch-build` + `bash scripts/tests/run.sh`;
manual run over all three classes.

---

## Phase 7: Hardening, CLI surface, docs

CI-safe polish: full option set (`--no-build`, `--no-install`, `--settle`,
`--lang`, `--udid <class>=<udid>`), pre-flight and post-flight `sips` size checks
against each class's accepted pair (mismatch exits 1 naming the file), a
clean-clone no-network determinism run, `make appstore-screenshots`, and an
"App Store screenshots" section in `AGENTS.md`.

**Files**: `scripts/appstore-screenshots.sh`, `Makefile`, `AGENTS.md`,
`scripts/tests/run.sh`

**Key changes**:
- `--udid` pin escape hatch; help header as the script's documentation
- `make appstore-screenshots` passthrough target
- AGENTS.md: command, seam flags, output tree, fixture dir, named-device exception

**Contract**: the capture run stays out of `scripts/test.sh`; `shellcheck` +
the harness remain the script's gate.

**Tests**: harness option-parse/`-h`/unknown-flag cases, pre-flight mismatch and
post-flight mismatch cases, `--no-build`/`--no-install` legs.
**Verify**: `bash scripts/tests/run.sh` + `shellcheck scripts/*.sh
scripts/tests/*.sh` + full `bash scripts/test.sh` prints `gate: ok`; two
consecutive manual runs produce identical PNG bytes.

---

## Testing Checkpoints

- After Phase 1: `make test-unit` and `bash scripts/tests/run.sh` green, one PNG
  at 1206×2622 — before any other screen.
- After Phase 3: seeded UI smoke green — before settings/detail seams.
- After Phase 4: all five iOS captures green — before the language loop.
- After Phase 5: six language folders — before adding classes.
- After Phase 6: all three classes + manifests — before hardening.
- After Phase 7: `shellcheck` + harness + `bash scripts/test.sh` → `gate: ok`;
  capture run still excluded from the gate.
