# Implementation Plan

## Overview

Add an **opt-in** `iphone-duo` device class to `scripts/appstore-screenshots.sh` that
captures the five CheckStitch screens in four variants (outer portrait/landscape, inner
portrait/landscape) at the exact App Store spec pixels, backed by two opt-in
`LaunchSeams` knobs (forced Duo-outer layout, forced orientation). Production
`DuoDisplay`/`DuoOuterPortrait` detection and its fail-safe are untouched. Three
pose-gated invocations cover all six languages.

Naming used throughout this plan:

- **variant** ∈ `outer-portrait` | `outer-landscape` | `inner-portrait` | `inner-landscape`
- **variant directory** = `iphone-duo-<variant>` (e.g. `iphone-duo-outer-portrait`)
- **pose** ∈ `folded` (default) | `book` | `open`; one Device Hub change per invocation
- `folded` → `outer-portrait` (display `1`) **and** `outer-landscape` (display `1`, forced landscape)
- `book` → `inner-portrait` (display `3`)
- `open` → `inner-landscape` (display `3`)

---

## Phase 1: Walking skeleton — folded outer portrait, end to end

**Goal:** `bash scripts/appstore-screenshots.sh --duo-pose folded iphone-duo` resolves the
Duo sim, installs, launches with `--ui-testing-force-duo-outer`, and writes six
`<lang>/iphone-duo-outer-portrait/*.png` at exactly 1398 × 2034 showing the widened Duo
card (resolve → boot → install → force seam → layout → `--display 1` capture → size gate).

### Changes

#### 1. Committed Duo wallpaper fixtures (prerequisite for staging)
**File**: `scripts/fixtures/appstore-wallpapers/iphone-duo-<screen>.jpg` (×5), `manifest.json`
**Action**: create/append

`stage_slot iphone-duo <screen>` reads `scripts/fixtures/appstore-wallpapers/manifest.json`
and exits 3 if the slot is absent, aborting the run (and the shell tests) under `set -e`.
The five slots are `iphone-duo-main-dark`, `iphone-duo-empty`, `iphone-duo-settings`,
`iphone-duo-main-light`, `iphone-duo-detail` — shared by all four variants.

After the `DEVICE_TYPES` edit in step 3, fetch them once with the existing flow (existing
10 slots are kept):

```
bash scripts/appstore-screenshots.sh --fetch-wallpapers
python3 -c "import json;d=json.load(open('scripts/fixtures/appstore-wallpapers/manifest.json'));print(sorted(k for k in d if k.startswith('iphone-duo-')))"
```

**Fallback if the endpoint is unavailable:** copy an existing committed photo and hand-add
the manifest entry (the app only stages `background.jpg`, so any licensed photo works):

```
cp scripts/fixtures/appstore-wallpapers/iphone-6.3-main-dark.jpg \
   scripts/fixtures/appstore-wallpapers/iphone-duo-main-dark.jpg   # repeat per screen
```

then add a JSON entry per slot mirroring an existing one
(`{file, source, photographer, photographerURL, fetchedAt}`). Keep `manifest.json`
`indent=2, sort_keys=True` (the fetch script rewrites it that way).

#### 2. `LaunchSeams` — `forceDuoOuter` seam
**File**: `CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift`
**Action**: modify

Add the field, the init parameter (at the end), and the parse case (each flag implies
`isUITesting`, like every existing flag):

```swift
public var forceDuoOuter: Bool

public init(
    isUITesting: Bool = false, isEmpty: Bool = false, seedURL: URL? = nil,
    openSettings: Bool = false, openChecklistIndex: Int? = nil,
    language: AppLanguage? = nil, forceDuoOuter: Bool = false
) {
    // …existing assignments…
    self.forceDuoOuter = forceDuoOuter
}
```

In `parse(arguments:environment:)`:

```swift
case "--ui-testing-force-duo-outer":
    seams.isUITesting = true; seams.forceDuoOuter = true
```

#### 3. `DuoOuterPortrait` — defaulted `forceDuoOuter` + live overload
**File**: `CheckStitch/DuoOuterPortrait.swift`
**Action**: modify

Short-circuit the machine/size-class predicate when forced; give the seam an explicit live
overload that reads the real launch seams (mirrors the design's "live overload passes
`LaunchSeams.current().forceDuoOuter`"). Remove the `machine` default so the two overloads
do not collide:

```swift
static func context(
    horizontal: UserInterfaceSizeClass?,
    vertical: UserInterfaceSizeClass?,
    machine: String,
    forceDuoOuter: Bool = false
) -> ChecklistLayout.Context {
    ChecklistLayout.Context(
        isDuoOuterPortrait: forceDuoOuter
            || DuoDisplay.isOuterPortrait(
                machine: machine,
                isCompactWidth: horizontal == .compact,
                isRegularHeight: vertical == .regular))
}

static func context(
    horizontal: UserInterfaceSizeClass?,
    vertical: UserInterfaceSizeClass?
) -> ChecklistLayout.Context {
    context(
        horizontal: horizontal, vertical: vertical,
        machine: machineIdentifier,
        forceDuoOuter: LaunchSeams.current().forceDuoOuter)
}
```

`ContentView.layoutContext` (`:460-461`) already calls the two-arg overload — no view
change. Production detection and its `.standard` fail-safe are untouched.

#### 4. `scripts/appstore-screenshots.sh` — Duo skeleton
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

**(a) Constants** — next to the watch constants:

```bash
DUO_CLASS=iphone-duo
DUO_PATTERN='iPhone Duo$'
DUO_POSE="${DUO_POSE:-folded}"
```

**(b) CLI** — add `--duo-pose` to the parse loop (validated at parse so a bad pose exits 2
before any capture); change the `--help` `sed` end line to the new last header line
(currently `2,30p`; see instruction in Verification):

```bash
    --duo-pose)           DUO_POSE=$2
                          case "$DUO_POSE" in
                            folded|book|open) ;;
                            *) echo "!! --duo-pose must be folded|book|open (got '$DUO_POSE')" >&2; exit 2 ;;
                          esac
                          shift 2 ;;
```

**(c) Device inventory** — one entry, newest runtime wins:

```bash
DEVICE_TYPES=( "iphone-6.3:iPhone 17$" "ipad-13:iPad Pro 13-inch \\(M5\\)" "iphone-duo:iPhone Duo$" )
```

**(d) Variant-aware `size_for`** — two args; non-Duo branches never reference `$2`, so the
existing one-arg calls keep working (bash dynamic scoping + matched-case-only evaluation):

```bash
size_for() { # $1 = class label, $2 = variant (iphone-duo only)
  case "$1" in
    iphone-6.3) echo "1206x2622" ;;
    ipad-13)    echo "2064x2752" ;;
    watch-46mm) echo "416x496" ;;
    iphone-duo)
      case "$2" in
        outer-portrait)  echo "1398x2034" ;;
        outer-landscape) echo "2034x1398" ;;
        inner-portrait)  echo "2007x2853" ;;
        inner-landscape) echo "2853x2007" ;;
      esac ;;
  esac
}
```

**(e) `device_name_for`** — add `iphone-duo) echo "iPhone Duo" ;;`.

**(f) `shoot` — optional `--display <id>`** (default omits the flag, so iPhone/iPad shots
stay byte-identical):

```bash
shoot() { # $1 = output path, optional `--display <id>`, rest = launch arguments
  local out=$1; shift
  local display=()
  if [ "${1:-}" = "--display" ]; then display=(--display "$2"); shift 2; fi
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  sleep 1
  SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE" \
    xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" "$@" >/dev/null
  sleep "$SETTLE"
  xcrun simctl io "$UDID" screenshot --mask ignored "${display[@]+"${display[@]}"}" "$out" >/dev/null
  echo "    ${out#"$OUT/"}"
}
```

**(g) `preflight_size` — optional display id** (existing two-arg callers unchanged):

```bash
preflight_size() { # $1 = udid, $2 = expected WxH, $3 = display id (optional)
  local tmp dims display=()
  if [ $# -ge 3 ]; then display=(--display "$3"); fi
  tmp=$(mktemp -t appstore-preflight).png
  xcrun simctl io "$1" screenshot --mask ignored "${display[@]+"${display[@]}"}" "$tmp" >/dev/null
  dims=$(sips -g pixelWidth -g pixelHeight "$tmp" | tail -2 | tr -dc '0-9\n' | paste -sd x -)
  rm -f "$tmp"
  if [ "$dims" != "$2" ]; then
    echo "!! simulator $1 captures ${dims}, expected ${2}" >&2; return 1
  fi
}
```

`verify_size` is reused unchanged; the variant pair is passed by the caller.

**(h) `grant_reminder_access`** — the EventKit prompt is a one-shot system alert that stays
on SpringBoard and bleeds into every later shot; pre-grant so it is never raised:

```bash
grant_reminder_access() { # $1 = simulator UDID
  xcrun simctl privacy "$1" grant reminders "$BUNDLE" >/dev/null 2>&1 || true
}
```

Call it after `boot_and_install "$UDID"` in **both** `capture_class` and `capture_duo`
(every iOS class; decision 11).

**(i) Duo pose helpers + capture** — dedicated `capture_duo`, mirroring `capture_watch`
(so `capture_class`'s capture shape stays untouched), with `duo_folder_for_pose` returning
the variant suffix and per-variant size gate + manifest:

```bash
duo_display_for_pose() { # $DUO_POSE → simctl --display id
  case "$DUO_POSE" in
    folded)    echo 1 ;;
    book|open) echo 3 ;;
  esac
}

duo_folder_for_pose() { # $DUO_POSE → variant folder suffix
  case "$DUO_POSE" in
    folded) echo "outer-portrait" ;;
    book)   echo "inner-portrait" ;;
    open)   echo "inner-landscape" ;;
  esac
}

# One variant folder: the five screens with the same per-stem args/appearance as
# capture_class, captured on `$display`, then the variant's own size gate and manifest.
duo_shoot_variant() { # $1 = lang, $2 = variant, $3 = display id, $4 = accepted size, rest = extra launch args
  local language=$1 variant=$2 display=$3 size=$4; shift 4
  local extra=("$@")
  local dir="$OUT/$language/iphone-duo-$variant"
  local entry slot stem
  local stems=()
  rm -rf "$dir"; mkdir -p "$dir"
  for entry in "${SCREENS[@]}"; do
    slot=${entry%%:*}; stem=${entry##*:}
    case "$stem" in
      *-dark)  xcrun simctl ui "$UDID" appearance dark ;;
      *-light) xcrun simctl ui "$UDID" appearance light ;;
    esac
    stage_slot "$DUO_CLASS" "$slot"
    case "$stem" in
      1-main-dark)  shoot "$dir/$stem.png" --display "$display" "${extra[@]+"${extra[@]}"}" --ui-testing --ui-testing-app-language "$language" ;;
      2-empty)      shoot "$dir/$stem.png" --display "$display" "${extra[@]+"${extra[@]}"}" --ui-testing --ui-testing-app-language "$language" --ui-testing-empty ;;
      3-settings)   shoot "$dir/$stem.png" --display "$display" "${extra[@]+"${extra[@]}"}" --ui-testing --ui-testing-app-language "$language" --ui-testing-open-settings ;;
      4-main-light) shoot "$dir/$stem.png" --display "$display" "${extra[@]+"${extra[@]}"}" --ui-testing --ui-testing-app-language "$language" ;;
      5-detail)     shoot "$dir/$stem.png" --display "$display" "${extra[@]+"${extra[@]}"}" --ui-testing --ui-testing-app-language "$language" --ui-testing-open-checklist 0 ;;
    esac
    verify_size "$dir/$stem.png" "$size"
    stems+=("$stem")
  done
  write_manifest "$language" "iphone-duo-$variant" "$(device_name_for "$DUO_CLASS")" "$UDID" "$size" "${stems[@]}"
}

capture_duo() { # $1 = device type regex; pose taken from $DUO_POSE
  local pattern=$1 udid variant size language
  udid=$(udid_override_for "$DUO_CLASS")
  [ -n "$udid" ] || udid=$(resolve_udid "$pattern" iOS)
  if [ -z "$udid" ]; then
    echo "!! no iPhone Duo simulator found matching '$pattern' — skipping iphone-duo." >&2
    echo "   The Duo device type needs the iPhone19,4 runtime. Check:" >&2
    echo "     xcrun simctl list runtimes | grep iPhone19,4" >&2
    echo "     xcrun simctl list devicetypes | grep 'iPhone Duo'" >&2
    return 0   # never abort the whole run: `return 1` would trip `set -e`
  fi
  variant=$(duo_folder_for_pose)
  size=$(size_for "$DUO_CLASS" "$variant")
  UDID=$udid
  boot_and_install "$UDID"
  grant_reminder_access "$UDID"
  # Preflight checks the display in its as-booted (un-rotated) geometry — the primary
  # variant's pair. The forced-landscape variant is rotated after launch, so it is
  # verified post-shot only (not preflight).
  preflight_size "$UDID" "$size" "$(duo_display_for_pose)"

  for language in "${LANGUAGES[@]}"; do
    duo_shoot_variant "$language" "$variant" "$(duo_display_for_pose)" "$size" --ui-testing-force-duo-outer
  done
  xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
}
```

**(j) Class whitelist + dispatch** — accept `iphone-duo`, and branch the `DEVICE_TYPES`
loop so `capture_class` is not invoked for it:

```bash
# whitelist
    iphone-6.3|ipad-13|watch-46mm|iphone-duo) ;;
    *) echo "!! unknown class: $wanted (expected iphone-6.3, ipad-13, watch-46mm or iphone-duo)" >&2; exit 2 ;;
```

```bash
for entry in "${DEVICE_TYPES[@]}"; do
  label=${entry%%:*}; pattern=${entry#*:}
  for wanted in "${CLASSES[@]}"; do
    [ "$wanted" = "$label" ] || continue
    case "$label" in
      iphone-duo) capture_duo "$pattern" ;;
      *)          capture_class "$label" "$pattern" "$(size_for "$label")" ;;
    esac
  done
done
```

Adding `iphone-duo` to `DEVICE_TYPES` also makes `slot_names()` (and therefore
`--fetch-wallpapers`) cover the five `iphone-duo-<screen>` slots.

**(k) Header doc** — add `iphone-duo  iPhone Duo, per-variant sizes (see below)` to the
"Known classes" list and the `--duo-pose folded|book|open` option line (full Duo section in
Phase 4). Update the `--help` `sed -n '2,Np'` end line to the last header line.

#### 5. Unit tests
**File**: `CheckStitchTests/LaunchSeamsTests.swift`
**Action**: modify

```swift
@Test(arguments: ["--ui-testing-force-duo-outer"])
func duoForceFlagTurnsOnUITesting(_ flag: String) {
    let seams = LaunchSeams.parse(arguments: [flag], environment: [:])
    #expect(seams.forceDuoOuter)
    #expect(seams.isUITesting)
}

@Test func duoForceFlagDefaultsOff() {
    #expect(LaunchSeams.parse(arguments: [], environment: [:]).forceDuoOuter == false)
}
```

**File**: `CheckStitchTests/DuoOuterPortraitTests.swift`
**Action**: create

Whole suite (new file; `@MainActor` because the app target's default actor isolation makes
`DuoOuterPortrait` members MainActor):

```swift
@testable import CheckStitch
import SwiftUI
import Testing

@MainActor
struct DuoOuterPortraitTests {
    @Test func duoMachineInCompactRegularIsDuoOuter() {
        #expect(DuoOuterPortrait.context(horizontal: .compact, vertical: .regular, machine: "iPhone19,4")
            == .init(isDuoOuterPortrait: true))
    }

    /// Sad: the Duo inner display (regular/regular) must not change the layout.
    @Test func duoMachineInRegularRegularIsStandard() {
        #expect(DuoOuterPortrait.context(horizontal: .regular, vertical: .regular, machine: "iPhone19,4") == .standard)
    }

    /// Sad: a non-Duo phone in the same size classes must not change the layout.
    @Test func nonDuoMachineInCompactRegularIsStandard() {
        #expect(DuoOuterPortrait.context(horizontal: .compact, vertical: .regular, machine: "iPhone17,1") == .standard)
    }

    /// Fail-safe: unknown/missing machine, or missing size classes.
    @Test func emptyMachineIsStandard() {
        #expect(DuoOuterPortrait.context(horizontal: .compact, vertical: .regular, machine: "") == .standard)
        #expect(DuoOuterPortrait.context(horizontal: nil, vertical: nil, machine: "iPhone19,4") == .standard)
    }

    /// Happy: the screenshot seam forces the Duo outer context where `uname` reports
    /// the host arch and the size class is regular/regular.
    @Test func forceFlagReturnsDuoContext() {
        #expect(DuoOuterPortrait.context(
            horizontal: .regular, vertical: .regular, machine: "arm64", forceDuoOuter: true)
            == .init(isDuoOuterPortrait: true))
    }

    @Test func machineIdentifierIsReadable() {
        #if os(iOS)
            #expect(!DuoOuterPortrait.machineIdentifier.isEmpty)
        #else
            #expect(DuoOuterPortrait.machineIdentifier.isEmpty)
        #endif
    }
}
```

#### 6. Shell tests
**File**: `scripts/tests/run.sh`
**Action**: modify

Add a Duo stub after `stub_appstore_capture` (`:575-608`) and cases after the appstore
cases. The xcrun stub serves an `iPhone Duo` device under an `iPhone19,4`-flavoured runtime
so `resolve_udid` picks `DUO-UDID-1`; the path-aware `sips` maps each variant folder to its
spec pair and the `appstore-preflight` temp file to the pose's native pair (passed in):

```bash
stub_appstore_duo() { # $1 = preflight WxH (the pose's native, un-rotated pair)
    local preflight="$1"
    new_stubs xcrun xcodebuild sips
    cat >"$STUB_ROOT/xcrun" <<STUB
#!/bin/bash
echo "\$*" >>"$STUB_ROOT/xcrun.log"
case "\$1 \$2" in
  "simctl list")
    echo '{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-27-2-iPhone19-4":[{"name":"iPhone Duo","udid":"DUO-UDID-1","state":"Shutdown"}],"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[{"name":"iPhone 17","udid":"IPHONE-UDID-1","state":"Shutdown"}]}}' ;;
  "simctl get_app_container")
    echo "$STUB_ROOT/container" ;;
  "simctl io")
    for last in "\$@"; do :; done
    mkdir -p "\$(dirname "\$last")"; : >"\$last" ;;
esac
exit 0
STUB
    chmod +x "$STUB_ROOT/xcrun"
    cat >"$STUB_ROOT/sips" <<STUB
#!/bin/bash
for last in "\$@"; do :; done
case "\$last" in
  *appstore-preflight*)          echo "pixelWidth: ${preflight%x*}"; echo "pixelHeight: ${preflight#*x}" ;;
  *iphone-duo-outer-landscape*)  echo "pixelWidth: 2034"; echo "pixelHeight: 1398" ;;
  *iphone-duo-inner-portrait*)   echo "pixelWidth: 2007"; echo "pixelHeight: 2853" ;;
  *iphone-duo-inner-landscape*)  echo "pixelWidth: 2853"; echo "pixelHeight: 2007" ;;
  *)                             echo "pixelWidth: 1398"; echo "pixelHeight: 2034" ;;
esac
STUB
    chmod +x "$STUB_ROOT/sips"
}

appstore_duo_folded_writes_outer_portrait() {
    stub_appstore_duo 1398x2034
    SETTLE=0 bash scripts/appstore-screenshots.sh --duo-pose folded --no-build iphone-duo >/dev/null 2>&1 || return 1
    [[ -d "build/appstore-screenshots/en/iphone-duo-outer-portrait" ]] || return 1
    grep -q -- '--display 1' "$STUB_ROOT/xcrun.log" || return 1
    grep -q -- '--ui-testing-force-duo-outer' "$STUB_ROOT/xcrun.log" || return 1
    local m="build/appstore-screenshots/en/iphone-duo-outer-portrait/manifest.json"
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));
assert d["class"]=="iphone-duo-outer-portrait", d; assert d["device"]=="iPhone Duo", d;
assert d["size"]=="1398x2034", d;
assert d["screens"]==["1-main-dark","2-empty","3-settings","4-main-light","5-detail"]' "$m" || return 1
}

appstore_duo_unknown_pose_exits_two() {
    local status
    set +e; bash scripts/appstore-screenshots.sh --duo-pose sideways iphone-duo >/dev/null 2>&1; status=$?; set -e
    [[ $status -eq 2 ]]
}

appstore_duo_missing_runtime_warns_and_continues() {
    stub_appstore_capture 1206x2622   # no iPhone Duo runtime in the inventory
    SETTLE=0 bash scripts/appstore-screenshots.sh --duo-pose folded --no-build iphone-duo >/dev/null 2>&1 || return 1
    # exit 0 (set -e safe) is asserted by the `|| return 1` above; no output dir created.
    [[ ! -d "build/appstore-screenshots/en/iphone-duo-outer-portrait" ]]
}

run_case appstore_duo_folded_writes_outer_portrait appstore_duo_folded_writes_outer_portrait
run_case appstore_duo_unknown_pose_exits_two appstore_duo_unknown_pose_exits_two
run_case appstore_duo_missing_runtime_warns_and_continues appstore_duo_missing_runtime_warns_and_continues
```

### Verification

#### Automated
- [x] `make test-unit` passes (new `DuoOuterPortraitTests` + `LaunchSeamsTests`)
- [x] `bash scripts/tests/run.sh` passes (new Duo cases; existing appstore cases unchanged)
- [x] `bash -n scripts/appstore-screenshots.sh` and `/bin/bash -n scripts/appstore-screenshots.sh` pass
- [x] `python3 -c "import json;d=json.load(open('scripts/fixtures/appstore-wallpapers/manifest.json'));assert len([k for k in d if k.startswith('iphone-duo-')])==5"` passes; all five JPEGs exist
- [x] `grep -n '^set -euo pipefail' scripts/appstore-screenshots.sh` → subtract 1 → update `sed -n '2,Np'`; `bash scripts/appstore-screenshots.sh --help` prints the whole block
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean

#### Manual
- [ ] `xcrun simctl list runtimes | grep iPhone19,4` reports the Duo runtime; Device Hub
      hinge pose is **folded**
- [ ] `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose folded iphone-duo`
      reports every size accepted; `build/appstore-screenshots/en/iphone-duo-outer-portrait/1-main-dark.png`
      is 1398 × 2034 and shows the widened Duo card (16 pt inset, `maxContentWidth = min(340, w*0.8)`)
- [ ] Record the resolved Duo UDID — later phases reuse `resolve_udid`

---

## Phase 2: Folded outer landscape, end to end

**Goal:** the same `--duo-pose folded` run additionally emits
`<lang>/iphone-duo-outer-landscape/*.png` at 2034 × 1398, launched with
`--ui-testing-orientation landscape`. Advertising **and** requesting landscape is the fix
for the reference's silent no-op.

### Changes

#### 1. `LaunchSeams` — orientation seam
**File**: `CheckStitchCore/Sources/CheckStitchCore/LaunchSeams.swift`
**Action**: modify

```swift
public enum Orientation: String, Sendable {
    case portrait
    case landscape
}

public var orientation: Orientation?
```

Init gains `orientation: Orientation? = nil`. Parse:

```swift
case "--ui-testing-orientation":
    seams.isUITesting = true
    if index + 1 < arguments.count, let value = Orientation(rawValue: arguments[index + 1]) {
        seams.orientation = value; index += 1
    }
```

Unknown tokens leave `orientation == nil` (flag still implies `isUITesting`).

#### 2. `OrientationPolicy` — forced-landscape mapping (cross-platform)
**File**: `CheckStitch/OrientationPreference.swift`
**Action**: modify

Add `import CheckStitchCore` at the top. Add a `.landscape` case and the forced initializer
(cross-platform so the macOS-hosted suite can test it); the UIKit mask lives in the existing
iOS-only extension:

```swift
enum OrientationPolicy: String, CaseIterable {
    case portrait
    case allButUpsideDown
    case landscape

    init(allowsLandscape: Bool) {
        self = allowsLandscape ? .allButUpsideDown : .portrait
    }

    /// A forced landscape wins over the stored preference; `nil`/`.portrait`
    /// fall back to `allowsLandscape`.
    init(forcedOrientation: LaunchSeams.Orientation?, allowsLandscape: Bool) {
        if forcedOrientation == .landscape {
            self = .landscape
        } else {
            self = OrientationPolicy(allowsLandscape: allowsLandscape)
        }
    }
}

#if os(iOS)
    extension OrientationPolicy {
        var mask: UIInterfaceOrientationMask {
            switch self {
            case .portrait: .portrait
            case .allButUpsideDown: .allButUpsideDown
            case .landscape: .landscape
            }
        }
    }
#endif
```

#### 3. `AppDelegate` — advertise and request
**File**: `CheckStitch/AppDelegate.swift`
**Action**: modify

Add `import CheckStitchCore`. Feed the delegate mask from the seam and request the geometry
when forced (`applicationDidBecomeActive` is launch-arg-gated, so it is harmless in
production):

```swift
func applicationDidBecomeActive(_: UIApplication) {
    Self.applyAppearance(AppearanceMode.load())
    Self.applyForcedOrientationIfNeeded()
}

/// Forces landscape when the screenshot harness passes
/// `--ui-testing-orientation landscape`. No-op for production launches.
static func applyForcedOrientationIfNeeded() {
    guard LaunchSeams.current().orientation == .landscape else { return }
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
          let controller = scene.keyWindow?.rootViewController
    else { return }
    controller.setNeedsUpdateOfSupportedInterfaceOrientations()
    scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { error in
        Self.logger.error(
            "Forced orientation request failed: \(error.localizedDescription, privacy: .public)")
    }
}

func application(
    _: UIApplication,
    supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
    OrientationPolicy(
        forcedOrientation: LaunchSeams.current().orientation,
        allowsLandscape: OrientationPreference().isLandscapeEnabled
    ).mask
}
```

`applyLock` keeps using `OrientationPolicy(allowsLandscape:).mask` — unchanged.

#### 4. `scripts/appstore-screenshots.sh` — outer-landscape variant
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

In `capture_duo`'s language loop, add the second variant (only for `folded`):

```bash
  for language in "${LANGUAGES[@]}"; do
    duo_shoot_variant "$language" "$variant" "$(duo_display_for_pose)" "$size" --ui-testing-force-duo-outer
    if [ "$DUO_POSE" = folded ]; then
      duo_shoot_variant "$language" outer-landscape 1 \
        "$(size_for "$DUO_CLASS" outer-landscape)" \
        --ui-testing-force-duo-outer --ui-testing-orientation landscape
    fi
  done
```

No new header lines, so the `sed` range is unchanged.

#### 5. Unit tests
**File**: `CheckStitchTests/LaunchSeamsTests.swift`
**Action**: modify

```swift
@Test func forcedLandscapeParses() {
    let seams = LaunchSeams.parse(arguments: ["--ui-testing-orientation", "landscape"], environment: [:])
    #expect(seams.orientation == .landscape)
    #expect(seams.isUITesting)
}

@Test func forcedPortraitParses() {
    #expect(LaunchSeams.parse(arguments: ["--ui-testing-orientation", "portrait"], environment: [:]).orientation == .portrait)
}

@Test func absentOrientationIsNil() {
    #expect(LaunchSeams.parse(arguments: [], environment: [:]).orientation == nil)
}

@Test func unknownOrientationTokenIsNil() {
    let seams = LaunchSeams.parse(arguments: ["--ui-testing-orientation", "sideways"], environment: [:])
    #expect(seams.orientation == nil)
    #expect(seams.isUITesting)
}
```

**File**: `CheckStitchTests/OrientationPreferenceTests.swift`
**Action**: modify

Add the forced-mapping cases **and update the existing `policySelectsTheLockForEachToggleValue`
assertion** (the new `.landscape` case changes `allCases`):

```swift
@Test
func forcedLandscapeBeatsThePreference() {
    #expect(OrientationPolicy(forcedOrientation: .landscape, allowsLandscape: true) == .landscape)
    #expect(OrientationPolicy(forcedOrientation: .landscape, allowsLandscape: false) == .landscape)
}

@Test
func nonLandscapeForcedValueFallsBackToPreference() {
    #expect(OrientationPolicy(forcedOrientation: .portrait, allowsLandscape: true) == .allButUpsideDown)
    #expect(OrientationPolicy(forcedOrientation: .portrait, allowsLandscape: false) == .portrait)
    #expect(OrientationPolicy(forcedOrientation: nil, allowsLandscape: true) == .allButUpsideDown)
    #expect(OrientationPolicy(forcedOrientation: nil, allowsLandscape: false) == .portrait)
}
```

In `policySelectsTheLockForEachToggleValue`, change the last assertion to:

```swift
#expect(OrientationPolicy.allCases.map(\.rawValue) == ["portrait", "allButUpsideDown", "landscape"])
```

(The test imports `@testable import CheckStitch`; add `import CheckStitchCore` for
`LaunchSeams.Orientation`.)

#### 6. Shell tests
**File**: `scripts/tests/run.sh`
**Action**: modify

Extend `appstore_duo_folded_writes_outer_portrait` (or add a sibling case) to assert the
second folder and forced orientation:

```bash
appstore_duo_folded_writes_outer_landscape() {
    stub_appstore_duo 1398x2034
    SETTLE=0 bash scripts/appstore-screenshots.sh --duo-pose folded --no-build iphone-duo >/dev/null 2>&1 || return 1
    [[ -d "build/appstore-screenshots/en/iphone-duo-outer-landscape" ]] || return 1
    grep -q -- '--ui-testing-orientation landscape' "$STUB_ROOT/xcrun.log" || return 1
    local m="build/appstore-screenshots/en/iphone-duo-outer-landscape/manifest.json"
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));
assert d["class"]=="iphone-duo-outer-landscape"; assert d["size"]=="2034x1398"' "$m" || return 1
}
run_case appstore_duo_folded_writes_outer_landscape appstore_duo_folded_writes_outer_landscape
```

### Verification

#### Automated
- [x] `make test-unit` passes (orientation parse + policy mapping, updated `allCases`)
- [x] `bash scripts/tests/run.sh` passes (both outer folders, forced-orientation arg logged)
- [x] `bash -n scripts/appstore-screenshots.sh` passes; `shellcheck scripts/*.sh scripts/tests/*.sh` clean

#### Manual
- [ ] `bash scripts/appstore-screenshots.sh --no-build --no-install --duo-pose folded iphone-duo`
      now yields both `iphone-duo-outer-portrait` and `iphone-duo-outer-landscape` for every language
- [ ] `iphone-duo-outer-landscape/1-main-dark.png` is genuinely rotated: 2034 × 1398
- [ ] **If forced landscape is still portrait, STOP** and re-open design decision 4 before Phase 3

---

## Phase 3: Inner display, both poses, end to end

**Goal:** `--duo-pose book` yields `<lang>/iphone-duo-inner-portrait/` at 2007 × 2853 and
`--duo-pose open` yields `<lang>/iphone-duo-inner-landscape/` at 2853 × 2007, both from
display `3`, with **no** app seam (the inner panel is regular/regular, so the standard
layout is correct and `--ui-testing-orientation` is a documented no-op there).

### Changes

#### 1. `scripts/appstore-screenshots.sh` — inner poses
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

`duo_display_for_pose` / `duo_folder_for_pose` / `size_for iphone-duo …` already contain
the `book`/`open` rows from Phase 1. Add the non-folded branch to `capture_duo`'s language
loop (the `folded` branch stays exactly as Phase 2):

```bash
  for language in "${LANGUAGES[@]}"; do
    if [ "$DUO_POSE" = folded ]; then
      duo_shoot_variant "$language" outer-portrait 1 \
        "$(size_for "$DUO_CLASS" outer-portrait)" --ui-testing-force-duo-outer
      duo_shoot_variant "$language" outer-landscape 1 \
        "$(size_for "$DUO_CLASS" outer-landscape)" \
        --ui-testing-force-duo-outer --ui-testing-orientation landscape
    else
      duo_shoot_variant "$language" "$(duo_folder_for_pose)" 3 \
        "$(size_for "$DUO_CLASS" "$(duo_folder_for_pose)")"
    fi
  done
```

(The primary `variant`/`size`/`preflight_size` computed before the loop already cover
`book`/`open`, because `duo_folder_for_pose` returns their suffixes.)

#### 2. Shell tests
**File**: `scripts/tests/run.sh`
**Action**: modify

```bash
appstore_duo_book_writes_inner_portrait() {
    stub_appstore_duo 2007x2853
    SETTLE=0 bash scripts/appstore-screenshots.sh --duo-pose book --no-build iphone-duo >/dev/null 2>&1 || return 1
    [[ -d "build/appstore-screenshots/en/iphone-duo-inner-portrait" ]] || return 1
    grep -q -- '--display 3' "$STUB_ROOT/xcrun.log" || return 1
    ! grep -q -- '--ui-testing-force-duo-outer' "$STUB_ROOT/xcrun.log" || return 1
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));
assert d["class"]=="iphone-duo-inner-portrait"; assert d["size"]=="2007x2853"' \
      "build/appstore-screenshots/en/iphone-duo-inner-portrait/manifest.json"
}

appstore_duo_open_writes_inner_landscape() {
    stub_appstore_duo 2853x2007
    SETTLE=0 bash scripts/appstore-screenshots.sh --duo-pose open --no-build iphone-duo >/dev/null 2>&1 || return 1
    [[ -d "build/appstore-screenshots/en/iphone-duo-inner-landscape" ]] || return 1
    python3 -c 'import json,sys; d=json.load(open(sys.argv[1]));
assert d["class"]=="iphone-duo-inner-landscape"; assert d["size"]=="2853x2007"' \
      "build/appstore-screenshots/en/iphone-duo-inner-landscape/manifest.json"
}

run_case appstore_duo_book_writes_inner_portrait appstore_duo_book_writes_inner_portrait
run_case appstore_duo_open_writes_inner_landscape appstore_duo_open_writes_inner_landscape
```

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `bash scripts/tests/run.sh` passes (book/open folders and exact pairs)

#### Manual
- [ ] Set the Device Hub pose to **book**; `bash scripts/appstore-screenshots.sh --no-build
      --no-install --duo-pose book iphone-duo` → `iphone-duo-inner-portrait/` = 2007 × 2853,
      standard 32-inset layout (confirms `isOuterPortrait` excludes regular/regular)
- [ ] Set the pose to **open**; `… --duo-pose open iphone-duo` → `iphone-duo-inner-landscape/` = 2853 × 2007
- [ ] **If `open` does not yield 2853 × 2007, STOP** and re-open design decision 4

---

## Phase 4: Hardening & documentation

**Goal:** a missing Duo runtime produces a clear, non-fatal diagnostic; the doc block fully
describes the Duo workflow; `iphone-duo` is confirmed **opt-in** (absent from the default
class list).

### Changes

#### 1. `scripts/appstore-screenshots.sh` — diagnostics
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

`capture_duo`'s unresolved-runtime path already names `iPhone19,4` and the two `simctl list`
probes and returns 0 (Phase 1). Confirm wording distinguishes "no Duo runtime" from the
generic skip and keep `return 0` (never `return 1` — it aborts the script under `set -e`).

#### 2. Header doc block + `--help` range
**File**: `scripts/appstore-screenshots.sh`
**Action**: modify

Rewrite the header's Duo material:

- the four variants/folders/pixels table
  (`outer-portrait` 1398 × 2034, `outer-landscape` 2034 × 1398, `inner-portrait` 2007 × 2853,
  `inner-landscape` 2853 × 2007)
- the three invocations + the Device Hub pose step, with observed panel sizes
  (outer 466 × 678, inner 669 × 951)
- the pose → display-id table (`folded` → 1, `book`/`open` → 3)
- both seams (`--ui-testing-force-duo-outer`, `--ui-testing-orientation landscape`)
- the ASC "Duo slot not live" note
- the five shared `iphone-duo-<screen>` wallpaper slots
- `Usage:` class list updated to include `iphone-duo` (opt-in)

Then update the `--help` `sed` end line:

```
grep -n '^set -euo pipefail' scripts/appstore-screenshots.sh   # end line = this - 1
```

Set `sed -n '2,<end>p'` accordingly.

#### 3. Wallpaper README count
**File**: `scripts/fixtures/appstore-wallpapers/README.md`
**Action**: modify

Update the committed-count wording (`ten` → `fifteen`) and note the five `iphone-duo-*`
slots are shared by all four Duo variants.

Note: `--fetch-wallpapers` already covers the new slots because `slot_names()` iterates
`DEVICE_TYPES` (Phase 1 step j); no `--fetch-wallpapers` default-count change.

### Verification

#### Automated
- [x] `make test-unit` passes
- [x] `bash scripts/tests/run.sh` passes
- [x] `bash -n scripts/appstore-screenshots.sh` and `/bin/bash -n scripts/appstore-screenshots.sh` pass
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean
- [x] `bash scripts/appstore-screenshots.sh --help` prints the entire doc block
- [x] `grep -q 'iphone-duo' scripts/appstore-screenshots.sh` and the default-class line still
      reads `CLASSES=(iphone-6.3)` (opt-in preserved)
- [x] Full gate: `./scripts/test.sh` prints `gate: ok`

#### Manual
- [ ] Full three-invocation sweep across all six languages (pose set in Device Hub before
      each): `--duo-pose folded`, then `--no-build --no-install --duo-pose book`, then
      `--no-build --no-install --duo-pose open` — all four variant folders present for every
      language and every size accepted
- [ ] Temporarily point the script at an inventory without the Duo runtime (or rename the
      device type) and confirm the warning prints and the script still exits 0, then restore

---

## Deviations from `structure.md`

1. **Duo preflight is per-display, not per-variant.** The forced-landscape variant is
   rotated *after* launch, so a pre-launch `preflight_size` for 2034 × 1398 would always
   fail. Phase 1 computes the primary variant's (un-rotated, as-booted) pair and passes it
   to a single `preflight_size` on the pose's display; every variant still gets its own
   post-shot `verify_size`. Same regression coverage, correct ordering.
2. **`--fetch-wallpapers` needs no code change.** Because `iphone-duo` joins
   `DEVICE_TYPES`, `slot_names()` already emits the five new slots, so Phase 4 only
   documents (and updates the README count).
3. **Test file names match this repo.** The plan adds `DuoOuterPortraitTests.swift` (this
   repo has no such suite today) and extends `OrientationPreferenceTests` for the forced
   mapping, per the structure's cross-platform `OrientationPolicy` refinement.

No open questions.
