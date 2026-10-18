# Design Discussion

## Current State

- CheckStitch has **no launch-argument seam anywhere**. Repo-wide grep for
  `ProcessInfo` / `CommandLine` / `arguments.contains` over `*.swift` returns
  nothing; the only arg-adjacent code is ordinary `UserDefaults` preference
  persistence (`AppearanceMode`, `OrientationPreference`,
  `AppLanguagePreference`). The single UI test launches with
  `XCUIApplication().launch()` and no arguments
  (`CheckStitchUITests/CheckStitchUITests.swift:14-15`). Research Q4.
- The app is dependency-injected in exactly one place: `MyApp.init()`
  (`CheckStitch/MyApp.swift:40-62`) constructs the store and nine VMs, and the
  scene injects eight `.environment(...)` values plus `\.locale`
  (`MyApp.swift:87-96`, iOS `:177-185`). Root view is always `ContentView`.
- Screen selection is three unrelated mechanisms, not a route enum: list vs
  empty is `listVM.checklists.isEmpty` (`ContentView.swift:48-62`), detail is a
  `NavigationStack` push via `path` (`ContentView.swift:140`, `:812-815`),
  settings is a sheet gated by `settingsVM.showsSettings` and opened by
  `settingsVM.begin(...)` (`ContentView.swift:438`, `SettingsViewModel.swift:15-23`).
- Data is owned by `@MainActor @Observable ChecklistStore`, constructed as
  `ChecklistStore(defaults: UserDefaults = AppGroup.defaults, key: "checklists.v1")`
  (`CheckStitchCore/.../ChecklistStore.swift:20-23`); it loads synchronously in
  `init` (`:44-99`) and persists one JSON envelope (version 6) via
  `ChecklistCodec` (`Checklist.swift:676-743`). A second channel mirrors the same
  payload through `NSUbiquitousKeyValueStore` (`ChecklistSyncing.swift:20-50`),
  and the phone pushes `.context(Data)` to the watch over WatchConnectivity
  (`ChecklistSyncCoordinator.swift`).
- The watch never persists: `WatchChecklistStore` is in-memory
  (`ChecklistSync.swift:262-307`), populated only by phone-pushed context; a
  fresh watch renders `ContentUnavailableView("No checklists")`
  (`WatchChecklistListView.swift:5-49`).
- App language is `AppLanguage` (`en, de, es, fr, ja, zh-Hans` + `.system`) with
  the raw value *being* the locale id (`AppLanguage.swift:5-17`), persisted
  under `UserDefaults` key `"appLanguage"` and injected as `\.locale` in both
  targets (`MyApp.swift:76,104`, `CheckStitchWatchApp.swift:13`).
- The background photo is a **network-fetched** Unsplash image persisted with a
  sidecar `background.json` carrying a photographer credit
  (`CheckStitch/BackgroundImageStore.swift:29-34,88,190`), i.e. non-deterministic
  at launch.
- Scripts are uniform `#!/bin/bash`, `set -euo pipefail`, mode `100755`
  (`scripts/test.sh`, `resolve-sim-udid.sh`, `run-simulator.sh`, `run-watch.sh`,
  `run-devices.sh`, `l10n-check.sh`), exercised by a stubbed harness
  (`scripts/tests/run.sh:19-46`) and shellchecked by the gate
  (`scripts/test.sh:125-130`).
- The reference `/Users/vardy/dev/SingleThread/scripts/appstore-screenshots.sh`
  (730 lines) does all of this today: classes `iphone-6.3 | ipad-13 |
  watch-series11-46mm`, `simctl` boot/install/launch/`io screenshot`, per-language
  loops, `sips` size verification, and a committed wallpaper fixture set (10
  JPEGs, 2.0 MB, keyed `<class>-<screen>`, real credits in `manifest.json`).

## Desired End State

`scripts/appstore-screenshots.sh` produces, per language and per display class:

```
build/appstore-screenshots/<lang>/<device>/<n>-<name>.png
build/appstore-screenshots/<lang>/<device>/manifest.json
```

- `<lang>` ∈ `en de es fr ja zh-Hans`; `<device>` ∈ `iphone-6.3 ipad-13 watch-46mm`.
- iOS screens: `1-main-dark`, `2-empty`, `3-settings`, `4-main-light`, `5-detail`.
- Watch screens: `1-list`, `2-detail`.
- Wallpaper slots `<class>-<screen>` staged into the app container before each
  shot, so every capture is byte-deterministic across reruns and machines.
- Each PNG verified with `sips` against its class's accepted pair
  (`1206x2622`, `2064x2752`, `416x496`) — mismatch exits 1, naming the file.

Verification: run the script from a clean clone with no network and no
pre-existing simulator data; two consecutive runs produce identical bytes for
every PNG, and `bash scripts/tests/run.sh` covers the script's behaviour with
stubbed `xcrun`/`sips`/`curl`.

## Patterns to Follow

- **Script conventions** — `#!/bin/bash`, `set -euo pipefail`, mode `100755`,
  positional/env overrides documented in `-h`
  (`scripts/run-watch.sh:18-26`, `scripts/test.sh:3-5`).
- **Device resolution by runtime name** — `simctl list devices available --json`
  filtered by family/newest runtime/name regex, as the reference does
  (`SingleThread/scripts/appstore-screenshots.sh:339-356`); `--require-id`
  rejection idioms live in `scripts/resolve-sim-udid.sh:9-39`.
- **Capture mechanism** — `simctl boot` → `bootstatus -b` → `install` →
  `launch --terminate-running-process` → sleep → `simctl io screenshot
  --mask ignored` (reference `:481-491`; `--mask ignored` per the
  `app-store-screenshots` skill).
- **Single interception point for launch state** — every seam reads from the
  same parsed value at `MyApp.init()` (`MyApp.swift:40-62`); do not scatter
  `ProcessInfo` reads through views.
- **Injected persistence** — `ChecklistStore(defaults:key:)`
  (`ChecklistStore.swift:20-23`) already takes its `UserDefaults`; isolation is
  a constructor argument, not new architecture.
- **Test shapes** — Swift Testing `struct <Thing>Tests` with `@Test`/`#expect`
  behaviour-named functions, `@MainActor` for anything touching the view model
  (AGENTS.md); shell cases use `run_case` + `new_stubs`
  (`scripts/tests/run.sh:19-46`).
- **Do NOT follow** — `scripts/run-simulator.sh:14-43` pins one UDID and opens a
  Simulator window; it is the wrong primitive for class-driven captures. Do not
  add a bare `name=` destination to any build/test command, and do not extend
  the gate with the multi-minute capture run.

## Design Decisions

1. **Seam mechanism** — one Core `LaunchSeams` type parses `CommandLine`
   arguments (`--ui-testing`, `--ui-testing-empty`, `--ui-testing-open-settings`,
   `--ui-testing-open-checklist <index>`, `--ui-testing-app-language <id>`) plus
   `CHECKSTITCH_UITEST_SEED=<path>` for the seed payload. Parsed in all build
   configurations; a missing flag is a zero-behaviour-change no-op. Why: the
   reference drives everything through args, and `MyApp.init()` is the single
   construction seam (`MyApp.swift:40-62`), so one parse covers the app.
2. **Screen set** — iOS `main-dark, empty, settings, main-light, detail`; watch
   `list, detail`. Why: no "reminder subscreen" exists in CheckStitch; detail is
   a one-line `path` append (`ContentView.swift:812-815`) whereas folder seeding
   adds envelope complexity for marginal marketing value.
3. **Seed isolation** — under `--ui-testing`, `ChecklistStore` is constructed
   against an ephemeral/volatile `UserDefaults` suite and the seed envelope is
   injected in memory; `ChecklistSyncService` (KVS) and the iOS
   `ChecklistSyncCoordinator` (WCSession) do not start. Why: it leaves the
   simulator's real App Group container (which `make run` also uses) untouched
   and makes reruns reproducible.
4. **Display classes** — reference devices, by user decision: `iPhone 17`
   (1206×2622), `iPad Pro 13-inch (M5)` (2064×2752), `Apple Watch Series 11
   (46mm)` (416×496, valid against `WATCHOS_DEPLOYMENT_TARGET = 26.0`). This
   **deviates from the ticket's "iPhone 6.9\"/6.5\"" wording** (recorded under
   Open Risks).
5. **Pre-flight + post-flight size checks** — the resolved UDID is accepted only
   if its native screenshot size matches the class's expected pair *before*
   capturing, and every written PNG is re-verified with `sips` afterwards; both
   failures exit 1. Why: the skill's "wrong simulator" failure is otherwise a
   silent multi-minute run producing unusable assets.
6. **Watch is standalone** — `CheckStitchWatchApp` parses the same `LaunchSeams`,
   seeds its own in-memory `WatchChecklistStore` (no `WCSession`) and applies the
   language directly through `AppLocaleState`. Why: WatchConnectivity activation
   across paired simulators is timing-dependent, and the watch store is plain
   in-memory state (`ChecklistSync.swift:262-307`), so seeding it needs no new
   architecture.
7. **Hermetic `--ui-testing` mode** — skip `SentryBootstrap`, `PurchaseService`,
   sync/KVS pushes, WCSession, background-photo fetch, and never present the
   paywall / EventKit destination prompt / conflict / folder dialogs;
   `--ui-testing` without a seed is the *empty* state. Why: screenshots are
   non-interactive, so "everything off except the UI" is the only useful
   contract, and research Q1 shows those surfaces otherwise appear at launch.
8. **Wallpapers: reference-style deterministic staging** — copy the reference's
   10 fixtures + `manifest.json` (real Unsplash credits, 2.0 MB) into
   `scripts/fixtures/appstore-wallpapers/`, remapped to CheckStitch slot keys
   (`<class>-main-dark|empty|settings|main-light|detail`), staged into the app
   container alongside a `background.json` built from the manifest entry. Keep
   the full fetch CLI (`--fetch-wallpapers`, `--refetch-wallpapers`,
   `--wallpaper-url`, `--wallpaper-dir`) so slots can be regenerated or
   overridden. No watch wallpaper slots (no background layer there).
9. **Script shape** — a new ~250-300 line script with the reference's structure
   (class loop → language loop → `shoot` helper → `sips` verification) but this
   repo's idioms: its own `simctl list --json` device lookup, its own
   `xcodebuild build -derivedDataPath build/appstore-dd`, and a
   `make appstore-screenshots` passthrough target.
10. **CLI surface** — positional classes (`iphone-6.3 ipad-13 watch-46mm`,
    default all), `--no-build`, `--no-install`, `--settle <s>`, `--lang <id>`,
    `--udid <class>=<udid>` override, help/unknown-flag handling (`-h` prints the
    script header, unknown `-*` exits 2). Why: parity with the reference plus a
    pin escape hatch for machines whose sims are named differently.
11. **Output naming** — ticket-literal folders (`<plain-lang>/<device>/`), screens
    numbered per class for drag order, and a per-run `manifest.json` recording
    class, device model, UDID, size pair and screen list.
12. **Test coverage** — Swift Testing `LaunchSeamsTests` in `CheckStitchTests/`
    (parse matrix, seed decode, unknown-flag tolerance, `--ui-testing` without
    seed → empty) plus UI-test cases for a seeded `--ui-testing` launch and an
    `--ui-testing-empty` launch (needs stable accessibility identifiers on list
    rows). Shell harness gains per-class cases, the `--no-build` leg, a
    size-mismatch failure case, and the option-parse/`-h` cases.
13. **Gate and docs** — the capture run is **not** added to the gate (it needs
    three simulator classes and minutes); `shellcheck` + the harness already
    cover the script. A short "App Store screenshots" section is added to the
    repo `AGENTS.md` (command, seam flags, output tree, fixture dir, the named-
    device exception), and the script carries a reference-style help header as
    its own documentation.

## What We're NOT Doing

- **Not** targeting the iPhone 6.9" (1320×2868) or 6.5" (1284×2778) classes —
  user chose the reference's 6.3" iPhone 17 device.
- **Not** capturing folders, paywall, import/export, prompt-scaling, conflict or
  permission-prompt screens.
- **Not** adding a 6.5" `sips -z` downscale path.
- **Not** driving the watch through a paired iPhone / real WatchConnectivity
  flow, and not using `simctl spawn defaults write AppleLanguages` + reboot.
- **Not** seeding into the real App Group `checklists.v1` key
  (`ChecklistStore.swift:799-813`), and not using the import path for seeding.
- **Not** adding the capture run to `scripts/test.sh`, and not adding an opt-in
  `GATE_SCREENSHOTS` leg.
- **Not** adding granular per-feature suppression flags; one hermetic
  `--ui-testing` mode only.
- **Not** introducing a route enum or restructuring the three screen-selection
  mechanisms (`ContentView.swift:48-62,140,438`).
- **Not** localizing any seam flag or adding new user-facing strings (so
  `LocalizationFixtures.requiredKeys` and `scripts/l10n-check.sh` are untouched).
- **Not** creating child tickets — all work lands on the main ticket.

## Open Risks

- **Class mismatch with the ticket text**: the ticket says "iPhone 6.9\"/6.5\""
  but the agreed devices produce 6.3". If the app record has no 6.9" slot and
  rejects 6.3" captures, a 6.5" downscale (`sips -z 2778 1284`) becomes mandatory
  — deliberately deferred, not designed for.
- **Seams ship in release builds**: `LaunchSeams` is parsed unconditionally, so a
  user could pass `--ui-testing` to the store build. Mitigation is that it only
  ever writes to an ephemeral suite, but App Review could still flag inert demo
  code; if that becomes a concern, wrap the parse in `#if DEBUG` and accept
  Debug-build captures.
- **Watch language path precedence was never resolved**: research left open
  whether a cold watch launch uses `AppLocaleState` (local `UserDefaults`) or a
  `.language` push. The arg seam bypasses the question by setting the locale
  directly, but this means the captured watch is *not* the production cold-launch
  path.
- **Wallpaper fixtures are reused photos from another app's store page**; the
  slot remap reuses images (`ipad-13-options.jpg` → `-settings`). Credits stay
  accurate, but the visual pairing with CheckStitch's screens is unverified.
- **`BackgroundImageStore` staging details** were read only at the
  metadata/container level; the exact path and file names the layer reads at
  launch must be confirmed against a real container dump before the staging
  helper is trusted.
- **List-row accessibility identifiers** may not exist yet; if rows are
  identified only by label, the seeded-list UI assertion needs a small
  `accessibilityIdentifier` addition to `checklistList` rows
  (`ContentView.swift:486-571`).
- **Shell-harness stubbing of `xcodebuild`/`curl`/`sips`** is new surface for
  `scripts/tests/run.sh`; the build and size-check legs may need more stubbing
  than the existing cases suggest.
- **Wallpaper staging reaches into the app container path**, which is an
  undocumented Apple layout (`simctl get_app_container`); a simulator update can
  move it and silently break staging (shots would still capture, just without a
  wallpaper).
