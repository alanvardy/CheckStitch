# Implementation Plan

## Overview

Change `scripts/run-devices.sh` so the regular iPhone and iPad legs run on
**simulators** by default, while the physical **iPhone Duo** (the only iOS
device still targeted by `devicectl`) and the **macOS** leg keep their current
behaviour. The Apple Watch leg stays physical via `scripts/run-watch.sh`.
`IOS_TARGET` selects `sim` (new default) or `device` (the old all-physical
behaviour). All work is shell: one script, its shell-test harness, and the
stubbed `xcrun`.

Recon-confirmed facts this plan relies on (from `medium.md` + locator report):

- Current `run-devices.sh`: knobs L34–41; physical discovery filter L81–132
  keeps `platform=="iOS"`, `deviceType in ("iPhone","iPad")`,
  `reality=="physical"`; iOS loop L165–205; macOS L208–228; watch L236–244;
  summary L246–256.
- Fixture `scripts/fixtures/devicectl-devices.json` already carries everything
  needed: `…007` Fixture iPhone (`iPhone17,1`), `…008` Fixture iPad DevMode Off
  (`iPad16,3`), `…009` **Fixture iPhone Duo** (`iPhone19,4`), `…010` simulated
  iPhone (`reality=="simulated"`, already excluded).
- `scripts/resolve-sim-udid.sh` accepts `platform=iOS Simulator,id=…` (printed
  verbatim) or `…,name=…` (resolved with `xcrun simctl list devices available`
  and an anchored `grep -F "$NAME ("`); prints the UDID on stdout, exits 1 on
  failure.
- Tests: `new_stubs <names…>` writes logging no-ops and prepends to `PATH`;
  `stub_ios_command` (run.sh L375) stubs `xcrun xcodebuild make open` and
  pre-creates `Debug-iphoneos/CheckStitch.app`. Cases pass
  `DEVICES_JSON_IN="$IOS_FIXTURE" RUN_MAC=0 RUN_WATCH=0 DERIVED_DATA="$STUB_ROOT/dd"`.
- Gate: `./scripts/test.sh`, which includes `bash scripts/tests/run.sh` and
  `shellcheck scripts/*.sh scripts/tests/*.sh`.

Decisions settled with the user: iPad sim default `iPad (A16)`; iPhone sim
resolution `SIM_IPHONE` → worktree `.simulator_id` (when valid) → `iPhone 17`;
name→UDID resolution reuses `scripts/resolve-sim-udid.sh`.

---

## Phase 1: Add the simulator leg behind `IOS_TARGET` (default stays `device`)

Purely additive: `IOS_TARGET` defaults to `device`, so the default run behaves
exactly as today. The new simulator path is exercised only when
`IOS_TARGET=sim` is passed. This is the walking skeleton of the new feature and
de-risks the flip in Phase 2.

Suggested commit: `feat: add opt-in iPhone/iPad simulator leg to run-devices.sh`

### Changes

#### 1. Configuration, validation and derived paths

**File**: `scripts/run-devices.sh`
**Action**: modify

Add to the overrides block (after `DERIVED_DATA`):

```bash
IOS_TARGET="${IOS_TARGET:-device}"      # sim | device
SIM_IPHONE="${SIM_IPHONE:-}"            # explicit iPhone simulator UDID
SIM_IPAD="${SIM_IPAD:-}"                # explicit iPad simulator UDID
DUO_DEVICE_ID="${DUO_DEVICE_ID:-}"      # pin the physical Duo by identifier
```

After `REPO_ROOT` is set, read and validate the worktree pin (mirror the gate's
UUID guard so a corrupt file never reaches `simctl` raw), and add the
simulator product path:

```bash
SIM_APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"

WORKTREE_SIM_ID=""
if [[ -f "$REPO_ROOT/.simulator_id" ]]; then
    _candidate="$(tr -d '[:space:]' <"$REPO_ROOT/.simulator_id")"
    if [[ "$_candidate" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]]; then
        WORKTREE_SIM_ID="$_candidate"
    fi
fi

if [[ "$IOS_TARGET" != "sim" && "$IOS_TARGET" != "device" ]]; then
    echo "❌ IOS_TARGET must be 'sim' or 'device' (got '$IOS_TARGET')." >&2
    exit 1
fi
```

Add the resolver wrapper (reuses the repo's single name→UDID implementation):

```bash
# $1 explicit UDID (may be empty), $2 default device name, $3 prefer worktree pin (0/1)
resolve_sim() {
    local destination
    if [[ -n "${1:-}" ]]; then
        destination="platform=iOS Simulator,id=$1"
    elif [[ "${3:-0}" -eq 1 && -n "$WORKTREE_SIM_ID" ]]; then
        destination="platform=iOS Simulator,id=$WORKTREE_SIM_ID"
    else
        destination="platform=iOS Simulator,name=$2"
    fi
    bash scripts/resolve-sim-udid.sh "$destination"
}
```

#### 2. Simulator leg

**File**: `scripts/run-devices.sh`
**Action**: modify

Move `failures=0` up so it starts before the new leg, then insert the simulator
leg between the physical-device loop and the macOS step (or directly after the
no-device handling — order relative to the device loop does not matter; keep the
existing message blocks intact):

```bash
# ── iPhone/iPad simulator leg ─────────────────────────────────────────────────
SIM_TOTAL=0
SIM_LAUNCHED=0
if [[ "$IOS_TARGET" == "sim" ]]; then
    sim_targets=(
      "iPhone|$(resolve_sim "${SIM_IPHONE:-}" "iPhone 17" 1 || true)"
      "iPad|$(resolve_sim "${SIM_IPAD:-}" "iPad (A16)" 0 || true)"
    )
    for entry in "${sim_targets[@]}"; do
        label="${entry%%|*}"
        udid="${entry#*|}"
        SIM_TOTAL=$((SIM_TOTAL + 1))
        if [[ -z "$udid" ]]; then
            echo "❌ Could not resolve a $label simulator — set SIM_${label^^} or check 'xcrun simctl list devices available'." >&2
            failures=$((failures + 1))
            continue
        fi
        echo ""
        echo "==> Booting the $label simulator ($udid)…"
        if ! xcrun simctl bootstatus "$udid" -b; then
            echo "❌ Failed to boot the $label simulator." >&2
            failures=$((failures + 1))
            continue
        fi
        open -a Simulator --args -CurrentDeviceUDID "$udid" >/dev/null 2>&1 || true
        echo "==> Building $SCHEME ($CONFIGURATION) for the $label simulator…"
        if ! xcodebuild -scheme "$SCHEME" \
          -destination "id=$udid" \
          -configuration "$CONFIGURATION" \
          -derivedDataPath "$DERIVED_DATA" \
          build; then
            echo "❌ Build failed for the $label simulator." >&2
            failures=$((failures + 1))
            continue
        fi
        if [[ ! -d "$SIM_APP_PATH" ]]; then
            echo "❌ Built app not found at $SIM_APP_PATH" >&2
            failures=$((failures + 1))
            continue
        fi
        echo "==> Installing on the $label simulator…"
        if ! xcrun simctl install "$udid" "$SIM_APP_PATH"; then
            echo "❌ Install failed on the $label simulator." >&2
            failures=$((failures + 1))
            continue
        fi
        echo "==> Launching on the $label simulator…"
        if ! xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID"; then
            echo "❌ Launch failed on the $label simulator." >&2
            failures=$((failures + 1))
            continue
        fi
        SIM_LAUNCHED=$((SIM_LAUNCHED + 1))
    done
fi
```

Add the simulator count to the success summary (only printed when non-zero, so
`device`-mode output is unchanged):

```bash
    summary="Installed and launched on ${#DEVICES[@]} device(s)"
    [[ "$SIM_LAUNCHED" -gt 0 ]] && summary="$summary and $SIM_LAUNCHED simulator(s)"
```

Update the header comment block and the macOS/watch doc lines to document
`IOS_TARGET`, `SIM_IPHONE`, `SIM_IPAD` and `DUO_DEVICE_ID`.

#### 3. Test stub for simulator resolution

**File**: `scripts/tests/run.sh`
**Action**: modify

Replace the `xcrun` no-op in `stub_ios_command` with a real stub that answers
`simctl list devices available` (the names must match the plan's defaults) and
logs everything else, and pre-create the simulator product dir:

```bash
stub_ios_command() {
    new_stubs xcrun xcodebuild make open
    IOS_FIXTURE="$PWD/scripts/fixtures/devicectl-devices.json"
    mkdir -p "$STUB_ROOT/dd/Build/Products/Debug-iphoneos/CheckStitch.app"
    mkdir -p "$STUB_ROOT/dd/Build/Products/Debug-iphonesimulator/CheckStitch.app"
    cat >"$STUB_ROOT/xcrun" <<STUB
#!/bin/bash
if [[ "\$1" == "simctl" && "\$2" == "list" && "\$3" == "devices" ]]; then
    printf '%s\n' \
      '    iPhone 17 (11111111-1111-1111-1111-111111111111) (Shutdown)' \
      '    iPad (A16) (22222222-2222-2222-2222-222222222222) (Shutdown)'
    exit 0
fi
echo "\$*" >>"$STUB_ROOT/xcrun.log"
exit 0
STUB
    chmod +x "$STUB_ROOT/xcrun"
}
```

#### 4. New simulator cases

**File**: `scripts/tests/run.sh`
**Action**: modify

Add, next to the existing `run_devices_*` cases, and register each with
`run_case`. A shared env prefix (keep it literal in each case):
`DEVICES_JSON_IN="$IOS_FIXTURE" RUN_MAC=0 RUN_WATCH=0 IOS_TARGET=sim
SIM_IPHONE=11111111-1111-1111-1111-111111111111
SIM_IPAD=22222222-2222-2222-2222-222222222222 DERIVED_DATA="$STUB_ROOT/dd"`.

- `run_devices_sim_installs_and_launches_both_simulators` (happy): asserts
  `xcrun.log` has `simctl install <iphone>`, `simctl install <ipad>`,
  `simctl launch --terminate-running-process <iphone> app.alanvardy.CheckStitch`,
  and `xcodebuild.log` has `-destination id=<iphone>` and `-destination id=<ipad>`.
- `run_devices_sim_prefers_the_worktree_simulator`: omits `SIM_IPHONE`; reads
  `worktree_udid="$(cat .simulator_id)"` and asserts `simctl install
  $worktree_udid`. When `.simulator_id` is absent, fall back to asserting the
  default `iPhone 17` UDID so the case still exercises the resolution path.
- `run_devices_sim_resolution_failure_is_fatal` (sad): re-stub `xcrun` with only
  the iPhone line in `simctl list`, leave `SIM_IPAD` unset; expect non-zero and
  output containing `Could not resolve`.
- `run_devices_sim_continues_after_a_simulator_build_failure` (sad): re-stub
  `xcodebuild` to exit 1 only for `id=22222222-…`; expect non-zero, the iPhone
  still installed, the iPad never installed, and output containing
  `Build failed for the iPad simulator`.

### Verification

#### Automated

- [x] `make build` passes (script is not compiled; this is the cheap smoke the gate starts with)
- [x] `bash scripts/tests/run.sh` passes — all existing `run_devices_*` cases still green under the unchanged `device` default, plus the four new `sim` cases
- [x] `shellcheck scripts/run-devices.sh scripts/tests/run.sh` passes
- [x] `IOS_TARGET=banana bash scripts/run-devices.sh` exits non-zero with the `IOS_TARGET must be` message

#### Manual

- [ ] `IOS_TARGET=device bash scripts/run-devices.sh` behaves exactly as today (physical phone/iPad/Duo, macOS, watch) — spot-check with `RUN_MAC=0 RUN_WATCH=0` against `DEVICES_JSON_IN`
- [ ] `IOS_TARGET=sim RUN_MAC=0 RUN_WATCH=0 bash scripts/run-devices.sh` boots the resolved iPhone and iPad simulators, opens the Simulator window, builds, installs and launches CheckStitch on each, and exits 0

---

## Phase 2: Flip the default to `sim` and narrow physical discovery to the Duo

Now the change users see: the default run resolves/boots the iPhone and iPad
simulators, and `devicectl` is used only for the physical iPhone Duo.

Suggested commit: `feat: default run-devices.sh to iPhone/iPad simulators and Duo-only physical`

### Changes

#### 1. Default and discovery filter

**File**: `scripts/run-devices.sh`
**Action**: modify

- Change the default: `IOS_TARGET="${IOS_TARGET:-sim}"`.
- Update the `==> Discovering paired iPhone/iPad devices…` echo to name the mode
  (e.g. `… (sim default: the physical iPhone Duo only)`) so the Duo-only filter
  is visible in the log.
- Pass the mode and Duo pin into the filter heredoc:
  `python3 - "$DEVICES_JSON" "$UNREACHABLE_LOG" "$IOS_TARGET" "$DUO_DEVICE_ID" <<'PY'`
  and read them as `mode = sys.argv[3]`, `duo_id = sys.argv[4]`.
- After the existing `platform`/`deviceType`/`reality` checks and before the
  Developer-Mode note, add the Duo-only narrowing (device mode is unchanged):

```python
if mode != "device":
    is_duo = (
        (duo_id and device.get("identifier") == duo_id)
        or "iphone duo" in name.lower()
        or hardware.get("productType") == "iPhone19,4"
    )
    if not is_duo:
        continue
```

#### 2. No-Duo messaging

**File**: `scripts/run-devices.sh`
**Action**: modify

In the `${#DEVICES[@]} -eq 0` block, after the unreachable branch, replace the
`RUN_MAC` branch with a sim-aware one:

```bash
    if [[ "$IOS_TARGET" == "sim" ]]; then
        echo "  (no reachable physical iPhone Duo found — running the iPhone/iPad simulator legs instead)"
    elif [[ "$RUN_MAC" -eq 1 ]]; then
        echo "  (no reachable iPhone/iPad found — macOS + Apple Watch run only)"
    else
        echo "❌ No reachable iPhone/iPad found." >&2
        echo "   Pair an iPhone/iPad, unlock it, and connect it to this Mac's Wi-Fi, then retry." >&2
        exit 1
    fi
```

The `UNREACHABLE_COUNT` branch above stays: an unreachable Duo is still a failed
step.

#### 3. Update the discovery/destination cases for the new default

**File**: `scripts/tests/run.sh`
**Action**: modify

- Rewrite `run_devices_discovers_every_physical_ios_device` →
  `run_devices_sim_default_targets_only_the_duo_physically`: with no
  `IOS_TARGET` (default `sim`), assert `device install app --device
  …009` is present, `…007` and `…008` are **not** in `xcrun.log`, and the sim
  installs happened.
- Keep `run_devices_builds_against_each_device_destination` but pass
  `IOS_TARGET=device`, preserving its assertion that every physical destination
  is built with `-allowProvisioningDeviceRegistration`.
- Keep `run_devices_continues_after_a_device_build_failure` but pass
  `IOS_TARGET=device` (its point — one device failing does not stop the others —
  only has multiple physical targets there).
- Keep `run_devices_rejects_unreadable_saved_inventory` and
  `run_devices_rejects_malformed_saved_inventory` unchanged; both still exit
  during discovery, before the simulator leg.
- Update the `run_case` registrations for any renamed function.

#### 4. New sim-default cases

**File**: `scripts/tests/run.sh`
**Action**: modify

- `run_devices_device_mode_targets_every_physical_device`: `IOS_TARGET=device`
  with the fixture asserts installs for `…007`, `…008`, `…009` and **no**
  `simctl install` in `xcrun.log`.
- `run_devices_sim_default_without_a_duo_is_not_fatal`: write a temp inventory
  under `$STUB_ROOT` (copy the fixture with the Duo entry removed, via
  `python3`) and point `DEVICES_JSON_IN` at it; with `IOS_TARGET` unset, expect
  exit 0, both simulators installed, and output containing
  `no reachable physical iPhone Duo`.
- `run_devices_sim_matches_the_duo_by_product_type`: write a temp inventory
  where the Duo's `deviceProperties.name` is `Fixture Handset` but
  `hardwareProperties.productType` stays `iPhone19,4`; with `IOS_TARGET` unset,
  assert `device install app --device …009` is present.

### Verification

#### Automated

- [x] `bash scripts/tests/run.sh` passes with the full updated case set
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` passes
- [x] `./scripts/test.sh` prints `gate: ok` (full gate, once, after Phase 2 commits)

#### Manual

- [ ] `bash scripts/run-devices.sh` with a Duo paired: boots both simulators and
      installs/launches CheckStitch on each, installs/launches on the Duo,
      builds signed macOS and launches it, and runs the physical watch leg
- [ ] `bash scripts/run-devices.sh` with no Duo paired: exits 0 with the
      "no reachable physical iPhone Duo" note, both simulator legs, macOS and
      watch still run
- [ ] `IOS_TARGET=device bash scripts/run-devices.sh` restores the old
      all-physical behaviour

---

## Out of scope / explicitly unchanged

- `scripts/run-watch.sh` and the watch leg stay physical (the reference moved
  its watch to a simulator; this ticket does not).
- The macOS leg keeps `make build-mac-signed` (the KVS/App-Group entitlement
  requirement) — do not adopt the reference's `CODE_SIGNING_ALLOWED=NO` build.
- `Makefile` targets, `scripts/resolve-sim-udid.sh`, `scripts/run-simulator.sh`
  are reused as-is; no schema, API, or app-UI change.
