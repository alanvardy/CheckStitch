# Implementation Plan

## Overview

Make `scripts/run-devices.sh` and its delegated `scripts/run-watch.sh` install
and launch on **every** paired physical iPhone/iPad — including a freshly paired
second phone ("iPhone Duo", `productType iPhone19,4`) — by (1) relaxing the
discovery filter to `reality == "physical"` with Developer Mode downgraded to a
note, and (2) building per device against `-destination "id=<udid>"` with
`-allowProvisioningUpdates -allowProvisioningDeviceRegistration` so each new
device is auto-registered. The shape is ported from the proven SingleThread
VAR-1166 implementation. Shell tests replay an offline `devicectl` inventory
fixture so the Duo-with-Developer-Mode-off and simulator-excluded cases are
covered without hardware.

**Decisions (locked):**
- Unreachable watch = failed step. `run-watch.sh` runs the generic
  `.watchOS` fallback build (so build/signing failures still surface) and then
  exits non-zero.
- The watch leg stays the single-named-watch `run-watch.sh`; no multi-watch
  discovery is added to `run-devices.sh` (that is outside `medium.md`'s scope).
- Test cases are folded into `scripts/tests/run.sh` (as `medium.md` states); no
  new top-level test script.
- `scripts/fixtures/devicectl-devices.json` is ported verbatim from
  `/Users/vardy/dev/SingleThread/scripts/fixtures/devicectl-devices.json`
  (10 devices; the iOS entries are what the checks exercise).

**Out of scope:** the SingleThread multi-watch discovery, summary block,
watch-launch-form retry, `WATCH_BUNDLE_ID` variable, and macOS-leg build
changes. Reference: commits `6895892a` and `7836a415` in `SingleThread`.

**Note the port is a translation, not a copy.** CheckStitch delegates the watch
to `scripts/run-watch.sh` (SingleThread inlines it in `run-devices.sh`), and
CheckStitch's `scripts/tests/run.sh` is one file (SingleThread splits out
`scripts/test-run-devices.sh`). Do not copy `test-run-devices.sh` verbatim.

---

## Phase 1: Discovery filter, offline seam, fixture, and offline filter tests

Walking skeleton: with the fixture replay seam in place, a run can discover the
Duo and exclude the simulator with no hardware.

### Changes

#### 1. New devicectl inventory fixture
**File**: `scripts/fixtures/devicectl-devices.json`
**Action**: create

Port `/Users/vardy/dev/SingleThread/scripts/fixtures/devicectl-devices.json`
verbatim. The entries the phase-1 checks rely on:

- `Fixture iPhone` — `CCCCCCCC-0000-0000-0000-000000000007`, iPhone, physical,
  Developer Mode `enabled`, reachable.
- `Fixture iPad DevMode Off` — `CCCCCCCC-0000-0000-0000-000000000008`, iPad,
  physical, Developer Mode `disabled`, reachable.
- `Fixture iPhone Duo` — `CCCCCCCC-0000-0000-0000-000000000009`, iPhone,
  `productType iPhone19,4`, physical, Developer Mode `disabled`, reachable.
- `Fixture iPhone Sim` — `DDDDDDDD-0000-0000-0000-000000000010`, iPhone,
  `reality: "simulated"` — must never be an install target.

#### 2. Offline inventory seam + discovery filter
**File**: `scripts/run-devices.sh`
**Action**: modify

Add the `DEVICES_JSON_IN` override next to the other config vars:

```bash
DEVICES_JSON_IN="${DEVICES_JSON_IN:-}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-devices-$$.json"
```

Replace the `xcrun devicectl list devices` discovery preamble with a seam that
replays a saved inventory offline:

```bash
if [[ -n "$DEVICES_JSON_IN" ]]; then
    echo "  (using the saved inventory in DEVICES_JSON_IN=$DEVICES_JSON_IN)"
    if ! cp "$DEVICES_JSON_IN" "$DEVICES_JSON" 2>/dev/null; then
        echo "❌ DEVICES_JSON_IN=$DEVICES_JSON_IN could not be read." >&2
        exit 1
    fi
    if ! python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$DEVICES_JSON" 2>/dev/null; then
        echo "❌ DEVICES_JSON_IN=$DEVICES_JSON_IN is not valid JSON." >&2
        exit 1
    fi
elif ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    echo "   Plug in a device, unlock it, and tap 'Trust', then retry." >&2
    exit 1
fi
```

In the embedded discovery `python3 - <<'PY'` block, harden the payload read,
add the `reality` guard, and relax Developer Mode:

```python
with open(sys.argv[2], "a", encoding="utf-8") as unreachable_log:
    result = payload.get("result") if isinstance(payload, dict) else None
    devices = result.get("devices", []) if isinstance(result, dict) else []
    for device in devices:
        hardware = device.get("hardwareProperties", {})
        props = device.get("deviceProperties", {})
        if hardware.get("platform") != "iOS":
            continue
        if hardware.get("deviceType") not in ("iPhone", "iPad"):
            continue
        # A paired iOS simulator shares platform/deviceType with a physical
        # device but is not a devicectl install target, so exclude it here the
        # same way the watch filter does.
        if hardware.get("reality") != "physical":
            continue
        name = props.get("name", "unknown device")
        # ... (existing unreachable check unchanged) ...
        # Developer Mode is required to run a development-signed build. Do not
        # pre-skip on it: every paired physical phone (e.g. a second iPhone)
        # must receive the build, and devicectl reports the real failure if
        # Developer Mode is off. Name the likely cause up front instead.
        if props.get("developerModeStatus") != "enabled":
            print(f"  (note: {name} has Developer Mode off — if the install below fails, enable Settings → Privacy & Security → Developer Mode on it)", file=sys.stderr)
        print(f"{device['identifier']}|{name}")
```

(The unreachable `connectionProperties` check stays exactly as it is.)

Update the zero-device / unreachable messages and the file header comment to
drop "Developer Mode enabled" as the discovery gate (Developer Mode is now a
note, so the wording is "no reachable iPhone/iPad found"):

```bash
❌ No reachable iPhone/iPad found.
   Pair an iPhone/iPad, unlock it, and connect it to this Mac's Wi-Fi, then retry.
```

Header block at the top of the file: change the discovery sentence from
"every paired iPhone/iPad that has Developer Mode enabled" to "every paired
physical iPhone/iPad (simulators excluded; Developer Mode off is noted, not
skipped)" and document `DEVICES_JSON_IN=…` in the overrides list.

#### 3. Offline filter tests
**File**: `scripts/tests/run.sh`
**Action**: modify

Add a new section after the run-watch/run-devices-watch cases (before the
macOS-entitlement section). The harness already defines `new_stubs` /
`run_case` and the file `cd`s to the repo root.

```bash
# --- run-devices.sh iOS discovery filter ------------------------------------

IOS_FIXTURE=""

# xcrun/xcodebuild/make/open are logging no-ops; the built app dir is
# pre-created so the install loop does not bail on a missing product. The
# inventory comes from DEVICES_JSON_IN, so no `devicectl list devices` stub is
# needed.
stub_ios_command() {
    new_stubs xcrun xcodebuild make open
    IOS_FIXTURE="$PWD/scripts/fixtures/devicectl-devices.json"
    mkdir -p "$STUB_ROOT/dd/Build/Products/Debug-iphoneos/CheckStitch.app"
}

run_devices_discovers_every_physical_ios_device() {
    stub_ios_command
    local out
    out="$(DEVICES_JSON_IN="$IOS_FIXTURE" RUN_MAC=0 RUN_WATCH=0 \
        DERIVED_DATA="$STUB_ROOT/dd" bash scripts/run-devices.sh 2>&1)" || return 1
    grep -q 'device install app --device CCCCCCCC-0000-0000-0000-000000000007' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'device install app --device CCCCCCCC-0000-0000-0000-000000000008' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'device install app --device CCCCCCCC-0000-0000-0000-000000000009' "$STUB_ROOT/xcrun.log" || return 1
    if grep -q 'DDDDDDDD-0000-0000-0000-000000000010' "$STUB_ROOT/xcrun.log"; then return 1; fi
    # Developer Mode off is a note, not a skip (the iPad and the Duo).
    [[ "$out" == *"Developer Mode off"* ]]
}

run_devices_rejects_unreadable_saved_inventory() {
    stub_ios_command
    local out status
    set +e
    out="$(DEVICES_JSON_IN="$STUB_ROOT/missing.json" RUN_MAC=0 RUN_WATCH=0 \
        DERIVED_DATA="$STUB_ROOT/dd" bash scripts/run-devices.sh 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"could not be read"* ]]
}

run_devices_rejects_malformed_saved_inventory() {
    stub_ios_command
    printf 'not json' >"$STUB_ROOT/bad.json"
    local out status
    set +e
    out="$(DEVICES_JSON_IN="$STUB_ROOT/bad.json" RUN_MAC=0 RUN_WATCH=0 \
        DERIVED_DATA="$STUB_ROOT/dd" bash scripts/run-devices.sh 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"not valid JSON"* ]]
}

run_case run_devices_discovers_every_physical_ios_device run_devices_discovers_every_physical_ios_device
run_case run_devices_rejects_unreadable_saved_inventory run_devices_rejects_unreadable_saved_inventory
run_case run_devices_rejects_malformed_saved_inventory run_devices_rejects_malformed_saved_inventory
```

### Verification
#### Automated
- [x] `bash scripts/tests/run.sh` passes (the three new cases report `ok:`)
- [x] `shellcheck scripts/run-devices.sh scripts/tests/run.sh` is clean
- [x] `/bin/bash -n scripts/run-devices.sh` is clean (system-bash parse check
      also runs as `scripts_parse_under_system_bash`)

#### Manual
- [ ] `DEVICES_JSON_IN=scripts/fixtures/devicectl-devices.json RUN_MAC=0 RUN_WATCH=0 bash scripts/run-devices.sh 2>&1 | grep Developer`
      prints two Developer Mode-off notes (iPad + Duo) and no simulator device.

---

## Phase 2: Per-device iOS build with auto-registration

Replaces the single `generic/platform=iOS` build, which has no destination
device and therefore never registers a freshly paired phone.

### Changes

#### 1. Per-device iOS build loop
**File**: `scripts/run-devices.sh`
**Action**: modify

Replace the "Build once for all devices" block with a per-device loop that also
carries the install/launch logic:

```bash
# ── Build + install + launch per iOS device ───────────────────────────────────
# Building against each device's own destination — rather than one
# generic/platform=iOS build — is what auto-registers a newly paired phone:
# -allowProvisioningDeviceRegistration only registers the *destination* device,
# so a generic destination leaves a new device out of the embedded provisioning
# profile and its install fails with 0xe8008012 ("This provisioning profile
# cannot be installed on this device"). The first device compiles; the rest only
# re-sign against the shared team profile, which now includes every registered
# device.
if [[ ${#DEVICES[@]} -gt 0 ]]; then
    for entry in "${DEVICES[@]}"; do
        device_id="${entry%%|*}"
        device_name="${entry#*|}"

        echo ""
        echo "==> Building $SCHEME ($CONFIGURATION) for ${device_name}…"
        if ! xcodebuild -scheme "$SCHEME" \
          -destination "id=$device_id" \
          -configuration "$CONFIGURATION" \
          -derivedDataPath "$DERIVED_DATA" \
          -allowProvisioningUpdates \
          -allowProvisioningDeviceRegistration \
          build; then
            echo "❌ Build failed for $device_name." >&2
            failures=$((failures + 1))
            continue
        fi

        if [[ ! -d "$APP_PATH" ]]; then
            echo "❌ Built app not found at $APP_PATH" >&2
            failures=$((failures + 1))
            continue
        fi

        echo "==> Installing on ${device_name}…"
        if ! xcrun devicectl device install app --device "$device_id" "$APP_PATH"; then
            echo "❌ Install failed on $device_name (is it unlocked?)." >&2
            failures=$((failures + 1))
            continue
        fi

        echo "==> Launching on ${device_name}…"
        if ! xcrun devicectl device process launch --terminate-existing --activate --device "$device_id" "$BUNDLE_ID"; then
            echo "❌ Launch failed on $device_name." >&2
            failures=$((failures + 1))
        fi
    done
fi
```

#### 2. Per-device build tests
**File**: `scripts/tests/run.sh`
**Action**: modify

Add next to the phase-1 cases:

```bash
run_devices_builds_against_each_device_destination() {
    stub_ios_command
    DEVICES_JSON_IN="$IOS_FIXTURE" RUN_MAC=0 RUN_WATCH=0 \
        DERIVED_DATA="$STUB_ROOT/dd" bash scripts/run-devices.sh >/dev/null 2>&1 || return 1
    grep -q -- '-destination id=CCCCCCCC-0000-0000-0000-000000000007' "$STUB_ROOT/xcodebuild.log" || return 1
    grep -q -- '-destination id=CCCCCCCC-0000-0000-0000-000000000009' "$STUB_ROOT/xcodebuild.log" || return 1
    grep -q -- '-allowProvisioningDeviceRegistration' "$STUB_ROOT/xcodebuild.log"
}

run_devices_continues_after_a_device_build_failure() {
    stub_ios_command
    # Fail the build only for the Duo destination; every other destination
    # succeeds.
    cat >"$STUB_ROOT/xcodebuild" <<STUB
#!/bin/bash
echo "\$*" >>"$STUB_ROOT/xcodebuild.log"
case "\$*" in
    *id=CCCCCCCC-0000-0000-0000-000000000009*) exit 1 ;;
esac
exit 0
STUB
    chmod +x "$STUB_ROOT/xcodebuild"
    local out status
    set +e
    out="$(DEVICES_JSON_IN="$IOS_FIXTURE" RUN_MAC=0 RUN_WATCH=0 \
        DERIVED_DATA="$STUB_ROOT/dd" bash scripts/run-devices.sh 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    # The other two physical devices still installed.
    grep -q 'device install app --device CCCCCCCC-0000-0000-0000-000000000007' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'device install app --device CCCCCCCC-0000-0000-0000-000000000008' "$STUB_ROOT/xcrun.log" || return 1
    # The failed Duo build was never installed.
    if grep -q 'device install app --device CCCCCCCC-0000-0000-0000-000000000009' "$STUB_ROOT/xcrun.log"; then return 1; fi
    [[ "$out" == *"Build failed for Fixture iPhone Duo"* ]]
}

run_case run_devices_builds_against_each_device_destination run_devices_builds_against_each_device_destination
run_case run_devices_continues_after_a_device_build_failure run_devices_continues_after_a_device_build_failure
```

### Verification
#### Automated
- [x] `bash scripts/tests/run.sh` passes (both new cases report `ok:`)
- [x] `shellcheck scripts/run-devices.sh scripts/tests/run.sh` is clean

#### Manual
- [ ] `DEVICES_JSON_IN=scripts/fixtures/devicectl-devices.json RUN_MAC=0 RUN_WATCH=0 bash scripts/run-devices.sh 2>&1 | grep 'Building CheckStitch'`
      names each of the three fixture devices.
- [ ] On real hardware later: a run against the Duo completes without
      `0xe8008012` (proof is the install, not this script's output — see the
      `devicectl` skill).

---

## Phase 3: Per-device watch build + auto-registration with generic fallback

The watch leg gets the same treatment. `run-watch.sh` keeps its single
named-watch resolution; when the watch is paired but unreachable (resolver exit
2) it runs the generic `.watchOS` build so build/signing failures surface, then
exits non-zero (unreachable is a failed step).

### Changes

#### 1. Resolve-status handling + per-device build + fallback
**File**: `scripts/run-watch.sh`
**Action**: modify

Replace the `WATCH_ID="$(python3 ...)" || { ...; exit 1; }` block with a
status-capturing form, so exit 2 (unreachable) is distinguishable from exit 3
(unknown/unpaired):

```bash
if WATCH_ID="$(python3 "$RESOLVER_SCRIPT" "$DEVICES_JSON" "$WATCH_NAME")"; then
    WATCH_RESOLVE_STATUS=0
else
    WATCH_RESOLVE_STATUS=$?
fi

# Exit 2 means the resolver matched the watch but its CoreDevice tunnel is
# down (off the wrist, paired iPhone asleep, wrong network). There is no
# install target, so build the generic watchOS target — this still surfaces a
# signing/compile failure — then fail the leg: an unreachable watch is a
# failed step, not a silent success.
if [[ "$WATCH_RESOLVE_STATUS" -eq 2 ]]; then
    echo "⚠️  '${WATCH_NAME}' is paired but unreachable — building the generic watchOS target only (nothing will be installed)." >&2
    echo "   Put the watch on your wrist, unlock its paired iPhone, keep it near this Mac, then retry. devicectl error 4016 means the same." >&2
    if ! xcodebuild -scheme "$WATCH_SCHEME" \
      -destination 'generic/platform=watchOS' \
      -configuration "$CONFIGURATION" \
      -derivedDataPath "$DERIVED_DATA" \
      -allowProvisioningUpdates \
      build; then
        echo "❌ Watch build failed (generic fallback)." >&2
        exit 1
    fi
    if [[ ! -d "$WATCH_APP" ]]; then
        echo "❌ Built watch app not found at $WATCH_APP" >&2
    fi
    echo "❌ ${WATCH_NAME} is unreachable — the app was built but not installed." >&2
    exit 1
fi

if [[ "$WATCH_RESOLVE_STATUS" -ne 0 ]]; then
    echo "❌ Could not resolve '${WATCH_NAME}' (unpaired or unknown)." >&2
    echo "   Pair it in Xcode → Window → Devices and Simulators, then retry." >&2
    exit 1
fi
```

Change the reachable build from the generic destination to the resolved device:

```bash
echo "==> Building ${WATCH_SCHEME} (${CONFIGURATION}) for ${WATCH_NAME}…"
xcodebuild -scheme "$WATCH_SCHEME" \
  -destination "id=$WATCH_ID" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
```

The existing app-exists check, `devicectl install`, and `process launch` blocks
stay unchanged. Update the file header comment to note the per-device build,
auto-registration, and the unreachable generic fallback.

#### 2. Watch-leg tests
**File**: `scripts/tests/run.sh`
**Action**: modify

In `run_watch_installs_and_launches_resolved_device`, add destination and
registration assertions:

```bash
    grep -q -- '-destination id=WATCH-UDID-1' "$STUB_ROOT/xcodebuild.log" || return 1
    grep -q -- '-allowProvisioningDeviceRegistration' "$STUB_ROOT/xcodebuild.log" || return 1
```

Rewrite `run_watch_errors_on_unreachable_device` — the unreachable fixture
(`transportType: null`) now takes the generic-fallback path, still exits
non-zero, and names the cause:

```bash
run_watch_errors_on_unreachable_device() {
    stub_watch_command
    mkdir -p "$STUB_ROOT/dd/Build/Products/Debug-watchos/CheckStitchWatch.app"
    cat >"$WATCH_FIXTURE" <<'JSON'
{"result":{"devices":[{"identifier":"WATCH-UDID-1","deviceProperties":{"name":"Test Watch"},"connectionProperties":{"transportType":null}}]}}
JSON
    local out status
    set +e
    out="$(DERIVED_DATA="$STUB_ROOT/dd" WATCH_NAME="Test Watch" bash scripts/run-watch.sh 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"unreachable"* ]] || return 1
    # Fallback built the generic watchOS target (never a device destination).
    grep -q -- 'generic/platform=watchOS' "$STUB_ROOT/xcodebuild.log"
}
```

Update the delegated run-devices watch case that asserts on the unreachable
message — `run_devices_watch_errors_on_unreachable_device` currently checks
`*"Could not resolve"*`; change it to `*"unreachable"*` (the unknown-device case
keeps `*"Could not resolve"*`). Also add the destination assertion to
`run_devices_watch_installs_and_launches_resolved_device`:

```bash
    grep -q -- '-destination id=WATCH-UDID-1' "$STUB_ROOT/xcodebuild.log" || return 1
```

### Verification
#### Automated
- [x] `bash scripts/tests/run.sh` passes (all run-watch and run-devices-watch
      cases report `ok:`)
- [x] `shellcheck scripts/run-watch.sh scripts/tests/run.sh` is clean
- [x] `/bin/bash -n scripts/run-watch.sh` is clean

#### Manual
- [ ] `./scripts/test.sh` prints `gate: ok` (full gate: `make build`,
      `make test`, `make build-mac`, `make watch-build`, `make widget-build`,
      `scripts/tests/run.sh`, `shellcheck`).
- [ ] On real hardware later: the watch leg installs without a provisioning
      error (verify the installed bundle on the watch — see the `devicectl`
      skill).

---

## Commit plan

One commit per phase, on the ticket branch:

1. `fix(VAR-1167): discover every paired physical iPhone/iPad (offline fixture)`
2. `fix(VAR-1167): build per device so a newly paired iPhone auto-registers`
3. `fix(VAR-1167): auto-register the Apple Watch with a generic build fallback`

The full gate (`./scripts/test.sh`) runs once after all three phases land.
