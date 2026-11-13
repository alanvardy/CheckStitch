# Structure Outline

## Approach

Add an **opt-in** `iphone-duo` device class to `scripts/appstore-screenshots.sh` that
resolves the Duo simulator, captures each integrated display with
`simctl io <udid> screenshot --display <1|3>`, and writes four flat variant folders
(`iphone-duo-outer-portrait`, `…-outer-landscape`, `…-inner-portrait`,
`…-inner-landscape`) at the four spec pixel pairs. Two opt-in `LaunchSeams` knobs let the
harness fire the Duo outer layout on the sim (`forceDuoOuter`) and pin landscape geometry
(`orientation`); production `DuoDisplay`/`DuoOuterPortrait` detection and its fail-safe are
untouched. Camera pose (`--duo-pose folded|book|open`) is an operator Device Hub step, so
three invocations cover all six languages.

**Two design refinements, both forced by existing conventions (not new decisions):**
1. The pure orientation mapping lives on the **cross-platform** `OrientationPolicy`
   (`OrientationPreference.swift:52-66`) as `init(forcedOrientation:allowsLandscape:)`,
   not on the `#if os(iOS)` `AppDelegate` — `CheckStitchTests` is macOS-hosted, so an
   iOS-gated helper is untestable. The delegate maps `.policy.mask`.
2. Design decision 12 is followed literally: missing Duo runtime **warns and skips**
   (`return 0`), never `exit 1`, and `iphone-duo` stays out of the default class list
   (decision 13) — the reference reversed both, this repo does not.

---

## Phase 1: Walking skeleton — folded outer portrait, end to end

`bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo` resolves the Duo
sim, installs, launches with `--ui-testing-force-duo-outer`, and writes six
`<lang>/iphone-duo-outer-portrait/*.png` at exactly 1398 × 2034 showing the **widened**
Duo card. Green proves resolve → boot → install → force seam → layout → `--display 1`
capture → per-variant size gate, the whole chain.

**Files**: `CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift`,
`CheckStitch/DuoOuterPortrait.swift`, `scripts/appstore-screenshots.sh`,
`CheckStitchTests/LaunchSeamsTests.swift`, `CheckStitchTests/DuoOuterPortraitTests.swift`,
`scripts/tests/run.sh`, `scripts/fixtures/appstore-wallpapers/iphone-duo-*.jpg` (+manifest)

**Key changes**:
- `LaunchSeams.forceDuoOuter: Bool` — new field; `--ui-testing-force-duo-outer` in
  `parse(arguments:environment:)` also sets `isUITesting` (like every existing flag).
- `DuoOuterPortrait.context(horizontal:vertical:machine:forceDuoOuter: Bool = false) -> ChecklistLayout.Context` — new defaulted param short-circuits the machine/size-class check; the live overload passes `LaunchSeams.current().forceDuoOuter`.
- Script: `DEVICE_TYPES += "iphone-duo:iPhone Duo$"`; `--duo-pose folded|book|open` CLI (unknown → exit 2); `shoot <out> [--display <id>] <args…>`; `capture_duo <pattern>` (warns + `return 0` when unresolved); `size_for <class> <variant>` + variant-aware `preflight_size`/`verify_size`; `grant_reminder_access()` after install; output `write_manifest` reused with `class` = variant label.
- Five `iphone-duo-<screen>` wallpaper JPEGs + manifest entries (slots: `main-dark`, `empty`, `settings`, `main-light`, `detail`), shared by all four variants.

**Contract**: CLI `--duo-pose <pose>`; `shoot` accepts `--display <id>`; launch flag
`--ui-testing-force-duo-outer`; output path `<lang>/iphone-duo-<variant>/<stem>.png`;
`size_for(class, variant)` is the single source of truth for each variant's pair
(1398×2034 for this one); outer panel = display `1`. Later slices extend this shape,
never re-shape it.

**Tests**: `DuoOuterPortraitTests.forceFlagReturnsDuoContext` (happy) alongside the
existing machine×size-class matrix (proves the seam stays opt-in);
`LaunchSeamsTests` parses the flag; `scripts/tests/run.sh` gains a `stub_appstore_duo`
case (fake `iPhone19,4` runtime → UDID, `simctl io --display` writes the file,
path-aware `sips` returns 1398×2034) asserting the folder, exact sizes, and manifest keys.
**Verify**: `make test-unit` && `bash scripts/tests/run.sh` && `bash -n scripts/appstore-screenshots.sh`
green; manual folded run (pose set in Device Hub) reports every size accepted and
`1-main-dark.png` shows the widened card.

---

## Phase 2: Folded outer landscape, end to end

The same `--duo-pose folded` run additionally emits
`<lang>/iphone-duo-outer-landscape/*.png` at 2034 × 1398, launched with
`--ui-testing-orientation landscape`. This front-loads the riskiest integration: the
reference found that *requesting* landscape without *advertising* it is a silent no-op.

**Files**: `CheckStitchCore/…/LaunchSeams.swift`, `CheckStitch/OrientationPreference.swift`,
`CheckStitch/AppDelegate.swift`, `scripts/appstore-screenshots.sh`,
`CheckStitchTests/LaunchSeamsTests.swift`, `CheckStitchTests/OrientationPreferenceTests.swift`,
`scripts/tests/run.sh`

**Key changes**:
- `LaunchSeams.Orientation: String { case portrait, landscape }` + `LaunchSeams.orientation: Orientation?` — `--ui-testing-orientation <raw>`, unknown token → `nil` (flag still implies `isUITesting`).
- `OrientationPolicy.init(forcedOrientation: LaunchSeams.Orientation?, allowsLandscape: Bool)` — returns `.landscape` (new case) when forced landscape, else `init(allowsLandscape:)`; extend the iOS-only `mask` with `.case landscape → .landscape`. Cross-platform, hence macOS-testable.
- `AppDelegate.application(_:supportedInterfaceOrientationsFor:)` builds the policy from `LaunchSeams.current().orientation`; new `applyForcedOrientationIfNeeded()` called from `applicationDidBecomeActive` requests `.iOS(interfaceOrientations: .landscape)` via the existing `requestGeometryUpdate` path.
- Script: folded branch shoots the five screens a second time with `--display 1
  --ui-testing-orientation landscape`; `size_for(_, "outer-landscape")` → 2034×1398.

**Contract**: `--ui-testing-orientation portrait|landscape` is the only orientation seam;
`iphone-duo-outer-landscape` folder and 2034×1398 pair. Depends on Phase 1 only through
`--duo-pose` / `shoot --display`.

**Tests**: `LaunchSeamsTests` orientation parse (landscape present, absent→nil, unknown→nil);
`OrientationPreferenceTests` forced-landscape mapping (forced beats `allowsLandscape` in
both states; `nil`/`portrait` falls back to preference). Shell: second folder + size asserted.
**Verify**: `make test-unit` && `bash scripts/tests/run.sh` green; manual folded run shows
both outer folders accepted and `outer-landscape/1-main-dark.png` genuinely rotated.
If `requestGeometryUpdate` is flaky on the Duo runtime, **stop** and re-open design
decision 4 before Phase 3.

---

## Phase 3: Inner display, both poses, end to end

`--duo-pose book` yields `<lang>/iphone-duo-inner-portrait/` at 2007 × 2853 and
`--duo-pose open` yields `<lang>/iphone-duo-inner-landscape/` at 2853 × 2007, both from
display `3`, with **no** app seam: the inner panel is regular/regular, so the standard
layout is correct and `--ui-testing-orientation` is a documented no-op there.

**Files**: `scripts/appstore-screenshots.sh`, `scripts/tests/run.sh`

**Key changes**:
- `duo_display_for_pose()` → `1` for `folded`, `3` for `book`/`open`;
  `duo_folder_for_pose()` → `outer-portrait` / `inner-portrait` / `inner-landscape`;
  `size_for` gains `2007x2853` and `2853x2007`; force-args and the landscape branch stay
  gated on `folded`.

**Contract**: the pose → display/folder/size table is total; no new app seam. Depends
only on Phase 1's CLI and `shoot --display`.

**Tests**: shell `stub_appstore_duo` cases for both poses asserting each folder and its
exact pair; `bash -n`. Manual: inner shots render the standard 32-inset layout (confirms
`isOuterPortrait` excludes regular/regular).
**Verify**: `make test-unit` && `bash scripts/tests/run.sh`; manual `--no-build --no-install
--duo-pose book|open iphone-duo` each accepted.

---

## Phase 4: Hardening & documentation

A missing Duo runtime produces a clear, non-fatal diagnostic; the doc block fully
describes the Duo workflow; `iphone-duo` is confirmed absent from the default class list.

**Files**: `scripts/appstore-screenshots.sh`

**Key changes**:
- `capture_duo`'s unresolved-runtime path distinguishes "no Duo runtime" (message naming
  `iPhone19,4` + the two `simctl list` probes) from a generic skip, and still `return 0`.
- Doc block (and its `--help` `sed -n '2,Np'` range) rewritten: the four variants/folders/
  pixels table, the three invocations + Device Hub pose step with observed panel sizes
  (outer 466 × 678, inner 669 × 951), pose → display-id table, both seams, the ASC
  "Duo slot not live" note, and the five shared wallpaper slots.
- `--fetch-wallpapers` covers the five `iphone-duo-*` slots; `Usage:` class list updated.

**Contract**: none new — operator-facing docs + diagnostics only.

**Tests**: `bash -n`; `shellcheck scripts/*.sh scripts/tests/*.sh`; `bash scripts/appstore-screenshots.sh --help`
prints the whole block. Manual: full three-invocation sweep across all six languages with
all four folders present and every size accepted; simulate a missing runtime and confirm
the warning, then restore.
**Verify**: `make test-unit` && `bash scripts/tests/run.sh` && `./scripts/test.sh` (full gate).

---

## Testing Checkpoints

- **After Phase 1**: `make test-unit` + `scripts/tests/run.sh` green; folded run accepted
  1398 × 2034. Record the resolved Duo UDID — later slices reuse `resolve_udid`.
- **After Phase 2**: orientation parse + policy mapping green; folded run now yields both
  outer folders. If landscape is still portrait, stop and re-open design decision 4.
- **After Phase 3**: all four variant folders produced across the three pose runs.
- **After Phase 4**: `make test-unit`, `bash scripts/tests/run.sh`, `bash -n`, shellcheck
  and the full `./scripts/test.sh` gate green; manual sweep documented.

No new test target, no `scripts/test.sh`/CI rewiring, no child tickets — all work lands on
this branch.
