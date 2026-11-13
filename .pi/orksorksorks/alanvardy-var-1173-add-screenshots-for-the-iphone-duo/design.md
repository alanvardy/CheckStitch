# Design Discussion

## Current State

`scripts/appstore-screenshots.sh` (415 lines) is simulator-only and captures two iOS
classes — `iphone-6.3:iPhone 17$` (1206×2622) and `ipad-13:iPad Pro 13-inch (M5)`
(2064×2752) — plus a watch leg (416×496) (`:82-98`). Screens are five stems
(`main-dark`, `empty`, `settings`, `main-light`, `detail`) paired with wallpaper
slots `<class>-<screen>` (`:106-112`); output is `<lang>/<device>/<n>-<name>.png`
with a per-run `manifest.json` (`:298-307`). It shells out: `resolve_udid` (`:246-259`),
`boot_and_install` (`:261-266`), appearance via `simctl ui` (`:318-325`), wallpaper
staging via `get_app_container` (`:226-244`), `shoot()` (`:268-277`) launching with the
seed env under `--ui-testing*`, and a strict size gate (`preflight_size` `:287-296`,
`verify_size` `:279-285`). There is **no orientation, display, pose or Duo concept**.

App-side, `LaunchSeams` is the sole `ProcessInfo` reader (`LaunchSeams.swift:7`): a
pure `parse(arguments:environment:)` (`:35-66`) over six fields (`:10-15`), each flag
implying `isUITesting`. It has **no orientation or Duo field** (research Q2, Q4).
Duo layout exists but is inert on the simulator: `DuoDisplay.isOuterPortrait` keys on
machine `iPhone19,4` **and** compact-width/regular-height (`DuoDisplay.swift:8-19`);
`DuoOuterPortrait.machineIdentifier` reads `hw.machine` via `uname` and returns `""`
on the simulator (`DuoOuterPortrait.swift:14-25`), so `.standard` always wins.
Orientation is controlled by `OrientationPreference` (UserDefaults `allowsLandscape`,
`OrientationPreference.swift:25`) + `OrientationPolicy.mask` (`:48-67`), advertised by
`AppDelegate.application(_:supportedInterfaceOrientationsFor:)` (`AppDelegate.swift:53-59`)
and applied on toggle by `applyLock` (`:38-51`). No launch seam primes it.

The reference (`SingleThread` VAR-1172, `done.md`) shipped this shape and found two
latent bugs: the Reminders TCC alert bleeds into every later shot, and forcing
landscape alone was a no-op until the delegate mask also advertised landscape.

## Desired End State

`bash scripts/appstore-screenshots.sh iphone-duo` (opt-in class) produces, per the six
languages, the five screens in four variants at exact spec pixels:

| variant / folder | pose | display | pixels |
|---|---|---|---|
| `iphone-duo-outer-portrait` | folded | 1 | 1398 × 2034 |
| `iphone-duo-outer-landscape` | folded + forced landscape | 1 | 2034 × 1398 |
| `iphone-duo-inner-portrait` | book | 3 | 2007 × 2853 |
| `iphone-duo-inner-landscape` | open | 3 | 2853 × 2007 |

`folded` is the default pose; one pose change in Device Hub covers all six languages,
so three invocations cover the four variants. Verification: the per-variant `sips`
gate accepts every PNG, each variant's `manifest.json` records its own size, and the
outer-portrait shots show the widened Duo card (`ChecklistLayout.horizontalInset` 16
vs 32, `maxContentWidth` `min(340, w*0.8)` vs `min(340, w*0.6)`,
`ChecklistLayout.swift:28-56`).

## Patterns to Follow

- **Single launch seam**: extend `LaunchSeams.parse` (`LaunchSeams.swift:35-66`); views
  never read `ProcessInfo` (research Cross-Cutting).
- **Opt-in argv, fail-safe default**: every new flag implies `isUITesting`
  (`LaunchSeams.swift:35-66`); absent ⇒ today's behaviour. Mirror
  `DuoDisplay`/`ChecklistLayout` fail-safe to `.standard` (`DuoDisplay.swift:13-19`).
- **Pure logic in Core, platform binding in app target**: seams in
  `CheckStitchCore`; `AppDelegate`/`DuoOuterPortrait` stay `#if os(iOS)` bindings.
- **Device-name anchoring**: mirror the anchored `iPhone 17$` regex (`:82`).
- **Separate capture path**: `capture_watch` (`:354-370`) is the precedent for a
  device shape sharing the seeding/appearance pipeline; `DuoOuterPortrait.context`
  (`DuoOuterPortrait.swift:27-36`) is the precedent for a platform-supplied context.
- **Shell-test convention**: `run_case`/`new_stubs` with stubbed `xcrun`/`sips`
  (`scripts/tests/run.sh:18-43`, `:575-608`); assert on `xcrun.log` and real files.
- **Swift Testing convention**: `struct <Thing>Tests`, behaviour-named `@Test`,
  `@Test(arguments:)` matrices, `@MainActor` only where EventKit/VM is touched.
- **Do NOT follow**: reading `SIMULATOR_MODEL_IDENTIFIER` in production detection, or
  changing `DuoOuterPortrait`'s documented fail-safe (`DuoOuterPortrait.swift:23-24`).
- **Do NOT follow**: `simctl io … screenConfig power` on the inner display — the pose
  lights it; powering it off crash-loops SpringBoard (reference `done.md`).

## Design Decisions

1. **Capture surface — simulator, per display**: use `simctl io <udid> screenshot
   --display <1|3>`; the Duo runtime (`…iOS-27-2-iPhone19-4`) yields the exact spec
   pairs. No `devicectl` physical path.
2. **Class shape — one `iphone-duo` entry, four flat variant directories**: `DEVICE_TYPES`
   gains `iphone-duo:iPhone Duo$` (`:82`); output is
   `<lang>/iphone-duo-<variant>/<stem>.png`, preserving the two-level tree and keeping
   wallpaper slots at five (`<class>-<screen>`, `:106-112`). Rejected four labels (would
   need 20 fixtures) and variant-in-stem (breaks the slot/stem contract).
3. **Variant size is variant-aware**: `size_for` (`:85-91`) becomes a function of
   `(class, variant)`; `preflight_size` (`:287-296`) and `verify_size` (`:279-285`) check
   each variant's own pair, so a mis-mapped variant cannot pass.
4. **Pose control — operator Device Hub step + `--duo-pose folded|book|open`**: no
   supported headless hinge API exists. `folded` (default) emits both outer variants
   (`--ui-testing-orientation landscape` for the second); `book`/`open` emit the inner
   portrait/landscape variants. Three invocations, one pose change each, covering all
   six languages.
5. **Dedicated `capture_duo`, preflight per variant**: mirror `capture_watch`
   (`:354-370`) so `capture_class` (`:316-341`) is untouched; run `preflight_size` once
   per variant inside the loop. Rejected branching `capture_class` (couples the plain
   classes to Duo specifics) and a new `run-duo.sh` (duplicates machinery).
6. **`shoot()` gains optional `--display <id>`**: `shoot <out> [--display <id>] <args…>`
   (`:268-277`); default omits the flag, so iPhone/iPad shots are byte-identical.
7. **Orientation seam — `LaunchSeams.orientation` + both delegate halves**:
   `--ui-testing-orientation portrait|landscape` parses into a new
   `LaunchSeams.Orientation?` field. Extract pure
   `AppDelegate.supportedOrientations(forcedOrientation:allowsLandscape:)`, fed by the
   delegate from `LaunchSeams.current()` (`AppDelegate.swift:53-59`), and add
   `applyForcedOrientationIfNeeded()` at `applicationDidBecomeActive` that requests the
   geometry via the existing `requestGeometryUpdate` path (`:48-50`). Advertising **and**
   requesting is the fix for the reference's landscape-no-op bug.
8. **Duo-outer force seam — `--ui-testing-force-duo-outer`**: add the flag to
   `LaunchSeams` and a `forceDuoOuter` parameter to
   `DuoOuterPortrait.context(horizontal:vertical:machine:forceDuoOuter:)`
   (`DuoOuterPortrait.swift:27-36`) that short-circuits the machine check. The
   size-class test and production detection/fail-safe are untouched.
9. **Wallpaper slots — five shared `iphone-duo-<screen>` fixtures**: commit five new
   JPEGs + manifest entries under `scripts/fixtures/appstore-wallpapers/`, fetched once
   via the existing flow; all four variants reuse them.
10. **Manifest — one per variant directory**: `write_manifest` (`:298-307`) is reused
    unchanged with `class` = variant label and `size` = that variant's pair.
11. **Reminders TCC pre-grant**: after install, `simctl privacy <udid> grant reminders
    <bundle>` for every iOS class, so the permission alert cannot bleed into shots.
12. **Missing Duo runtime — warn and skip**: when `iphone-duo` is explicitly requested
    but no matching runtime exists, print a warning and continue other classes; never
    `return 1` from the class loop (aborts the whole script under `set -e`) and never
    fail silently.
13. **Opt-in class**: `iphone-duo` is **not** added to the default run (today a bare
    invocation is `iphone-6.3`, `:372`); App Store Connect's Duo slot is not live, so
    assets are produced on demand.
14. **Tests — both legs**: Swift cases in `LaunchSeamsTests` (parse of both new flags)
    and a pure `AppDelegate.supportedOrientations` mapping suite; `scripts/tests/run.sh`
    cases stubbing a Duo runtime/UDID and `simctl io --display`, asserting the four
    variant folders at their exact sizes, per-variant manifest keys, and an unknown
    `--duo-pose` exiting 2. `bash -n`/shellcheck stay green (bash 3.2, no assoc arrays).

## What We're NOT Doing

- No physical-device / `devicectl` capture path.
- No change to `DuoDisplay`/`DuoOuterPortrait` production detection or its fail-safe; no
  `SIMULATOR_MODEL_IDENTIFIER` read in production.
- No headless hinge automation, private CoreSimulator helper, or `baguette`/Appium.
- No inner-display `screenConfig power` manipulation.
- No 20 per-variant wallpaper fixtures; no per-variant `DEVICE_TYPES` labels.
- No `iphone-duo` in the default class list; no `--fetch-wallpapers` default-count change.
- No new test target; no `scripts/test.sh` / CI rewiring; the screenshot script stays
  outside the gate (its new cases run in `run.sh`, which is in the gate).
- No child tickets — all work lands on this branch.

## Open Risks

- **Pose precision**: exact hinge angles for `book` vs `open` are runtime/operator
  dependent; the doc block must record the observed panel sizes (466 × 678 outer,
  669 × 951 inner) and the Device Hub step.
- **Inner orientation**: the inner display ignores supported orientations, so
  `--ui-testing-orientation` is expected to be a no-op there; inner orientation is
  pose-driven. If `open` does not yield 2853 × 2007, re-open decision 4.
- **Runtime dependency**: the Duo device type needs runtime `iOS-27-2-iPhone19-4` (or
  later Duo runtime); the plain 27.2 runtime rejects it. The script must distinguish
  "no matching Duo runtime" from a generic skip.
- **Inner layout expectation**: inner is regular/regular, so `isOuterPortrait` is false
  and the standard 32-inset layout is correct — confirm the captured inner shots match.
- **TCC grant necessity**: decision 11 is defensive; if the manual Duo sweep shows no
  alert, the grant is harmless but unverified.
- **ASC not live**: uploaded Duo assets may be rejected until App Store Connect opens
  the slot; note it in the PR and the script doc block.
- **Manual verification only**: pose-dependent capture cannot be exercised headlessly;
  the four-variant sweep is a documented operator step, not a gate leg.
