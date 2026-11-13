#!/bin/bash
set -euo pipefail

# scripts/run-devices.sh — build CheckStitch for iOS, install + launch it on
# every paired physical iPhone/iPad (via devicectl) and/or on the iPhone/iPad
# simulators, plus (by default) the host Mac and the paired Apple Watch (via
# the run-watch.sh leg).
#
#   ./scripts/run-devices.sh
#
# Overrides (same env-override pattern as the Makefile):
#   SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
#   IOS_TARGET=sim|device # run the regular iPhone/iPad legs on simulators or
#                         # on physical devices (default sim; in sim mode only
#                         # the physical iPhone Duo is installed to over
#                         # devicectl; Developer Mode off is noted, not skipped)
#   SIM_IPHONE=… # pin the iPhone simulator by UDID (default: worktree
#                # .simulator_id when valid, else `iPhone 17`)
#   SIM_IPAD=…   # pin the iPad simulator by UDID (default: `iPad (A16)`)
#   DUO_DEVICE_ID=… # pin the physical iPhone Duo by identifier
#   DEVICES_JSON_IN=… # replay a saved `devicectl list devices -j` inventory
#                     # offline instead of querying devicectl (tests/fixtures)
#   RUN_MAC=0   # skip the macOS build + launch step (default RUN_MAC=1)
#   RUN_WATCH=0 # skip the Apple Watch build + launch step (default RUN_WATCH=1)
#
# Devices are discovered dynamically each run, so a new iPhone/iPad is picked
# up without editing this script. A device that is unreachable (locked, asleep,
# off this Wi-Fi, unplugged mid-run) is detected during discovery and reported
# — the remaining devices still get built and run; an unreachable device counts
# as a failed step so the run exits non-zero. If no iOS devices are found and
# RUN_MAC=1, the script still does the macOS step (and, with RUN_WATCH=1, the
# Apple Watch leg); set RUN_MAC=0 to keep the old fail-fast behavior. The macOS app is built signed (make build-mac-signed)
# so the App Group / KVS entitlements from AppGroup.entitlements land in the
# embedded provisioning profile and the key-value store syncs through iCloud.
# The Apple Watch leg stays physical via run-watch.sh.
#
# IOS_TARGET=sim runs the iPhone and iPad legs on simulators instead (reusing
# resolve-sim-udid.sh for name→UDID resolution); IOS_TARGET=device keeps the
# all-physical behaviour above.

# === Configuration (overridable) ===
SCHEME="${SCHEME:-CheckStitch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
IOS_TARGET="${IOS_TARGET:-sim}"         # sim | device
SIM_IPHONE="${SIM_IPHONE:-}"            # explicit iPhone simulator UDID
SIM_IPAD="${SIM_IPAD:-}"                # explicit iPad simulator UDID
DUO_DEVICE_ID="${DUO_DEVICE_ID:-}"      # pin the physical Duo by identifier
RUN_MAC="${RUN_MAC:-1}"
RUN_WATCH="${RUN_WATCH:-1}"
DEVICES_JSON_IN="${DEVICES_JSON_IN:-}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-devices-$$.json"
UNREACHABLE_LOG="${TMPDIR:-/tmp}/run-devices-unreachable-$$.log"
trap 'rm -f "$DEVICES_JSON" "$UNREACHABLE_LOG"' EXIT

# === Derived paths ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"
MAC_APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/${SCHEME}.app"
SIM_APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphonesimulator/${SCHEME}.app"

# The worktree pin is shared with the gate, so mirror the gate's UUID guard: a
# corrupt .simulator_id must never reach simctl raw.
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

cd "$REPO_ROOT"

# ── Discover devices ─────────────────────────────────────────────────────────
echo "==> Discovering paired iPhone/iPad devices… (sim default: the physical iPhone Duo only)"
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

# Emits "identifier|name" per qualifying device (platform iOS, iPhone or iPad,
# physical). Skipped devices go to stderr so stdout stays parseable;
# unreachable qualifying devices are logged to "$UNREACHABLE_LOG" for the failure
# tally, so a phone that is locked / off-network / has Remote Device Services down
# is reported with the real reason instead of a raw devicectl 4016 install error.
DEVICES=()
while IFS= read -r entry; do
    DEVICES+=("$entry")
done < <(python3 - "$DEVICES_JSON" "$UNREACHABLE_LOG" "$IOS_TARGET" "$DUO_DEVICE_ID" <<'PY'
import json
import sys

mode = sys.argv[3]
duo_id = sys.argv[4]

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

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
        # device but is not a devicectl install target, so exclude it here by
        # reality (the watch resolver matches by name only, so it has no such
        # check to share).
        if hardware.get("reality") != "physical":
            continue
        name = props.get("name", "unknown device")
        # sim mode narrows physical discovery to the iPhone Duo: the regular
        # iPhone/iPad legs run on simulators, so only the Duo is installed to
        # over devicectl. A device counts as the Duo when pinned by identifier,
        # named "iPhone Duo", or identified by its productType.
        if mode != "device":
            is_duo = (
                (duo_id and device.get("identifier") == duo_id)
                or "iphone duo" in name.lower()
                or hardware.get("productType") == "iPhone19,4"
            )
            if not is_duo:
                continue
        # Developer Mode is required to run a development-signed build. Do not
        # pre-skip on it: every paired physical phone (e.g. a second iPhone)
        # must receive the build, and devicectl reports the real failure if
        # Developer Mode is off. Name the likely cause up front instead.
        if props.get("developerModeStatus") != "enabled":
            print(f"  (note: {name} has Developer Mode off — if the install below fails, enable Settings → Privacy & Security → Developer Mode on it)", file=sys.stderr)
        # Physical devices install over a connection (localNetwork, wired, or
        # sameMachine for local simulators). When CoreDevice cannot reach the
        # device — locked, asleep, on another network, or Remote Device
        # Services down — devicectl fails every later call with a raw
        # usage-assertion error (4016). Detect it here so the message names
        # the actual problem before any build/install work is wasted.
        conn = device.get("connectionProperties", {}) or {}
        conn_state = (((device.get("properties") or {}).get("connection")) or {}).get("state")
        if conn.get("transportType") is None or conn_state == "unavailable" or conn.get("tunnelState") == "unavailable":
            print(f"  (skipping {name} — unreachable (locked, asleep, or on another network?)\n    unlock it, confirm it is on the same Wi-Fi as this Mac, then retry)", file=sys.stderr)
            print(name, file=unreachable_log)
            continue
        print(f"{device['identifier']}|{name}")
PY
)

UNREACHABLE_COUNT=0
if [[ -s "$UNREACHABLE_LOG" ]]; then
    UNREACHABLE_COUNT=$(wc -l < "$UNREACHABLE_LOG" | tr -d ' ')
fi

if [[ ${#DEVICES[@]} -eq 0 ]]; then
    if [[ "$UNREACHABLE_COUNT" -gt 0 ]]; then
        echo "❌ $UNREACHABLE_COUNT device(s) found but unreachable — see messages above (unlock the device and connect it to this Mac's Wi-Fi, then retry)." >&2
        exit 1
    fi
    if [[ "$IOS_TARGET" == "sim" ]]; then
        echo "  (no reachable physical iPhone Duo found — running the iPhone/iPad simulator legs instead)"
    elif [[ "$RUN_MAC" -eq 1 ]]; then
        echo "  (no reachable iPhone/iPad found — macOS + Apple Watch run only)"
    else
        echo "❌ No reachable iPhone/iPad found." >&2
        echo "   Pair an iPhone/iPad, unlock it, and connect it to this Mac's Wi-Fi, then retry." >&2
        exit 1
    fi
fi

failures=0
# Devices that are paired but unreachable count as failed steps, matching the
# old behavior where the guaranteed-failing install attempt was tried and failed.
failures=$((failures + UNREACHABLE_COUNT))

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

# ── iPhone/iPad simulator leg ─────────────────────────────────────────────────
# Opt-in via IOS_TARGET=sim. Resolution reuses resolve-sim-udid.sh; a simulator
# that cannot be resolved or fails to boot/build/install/launch is a failed step
# that does not stop the remaining leg (or the macOS/watch legs).
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

# ── macOS (host) step ──────────────────────────────────────────────────────────
if [[ "$RUN_MAC" -eq 1 ]]; then
    echo ""
    echo "==> Building $SCHEME ($CONFIGURATION) for macOS (signed)…"
    if ! make build-mac-signed \
      SCHEME="$SCHEME" \
      CONFIGURATION="$CONFIGURATION" \
      DERIVED_DATA="$DERIVED_DATA"; then
        echo "❌ macOS build failed." >&2
        failures=$((failures + 1))
    elif [[ ! -d "$MAC_APP_PATH" ]]; then
        echo "❌ Built macOS app not found at $MAC_APP_PATH" >&2
        failures=$((failures + 1))
    else
        echo "==> Launching $BUNDLE_ID on macOS…"
        if ! open "$MAC_APP_PATH"; then
            echo "❌ Failed to open $MAC_APP_PATH" >&2
            failures=$((failures + 1))
        fi
    fi
fi

# ── Apple Watch step ─────────────────────────────────────────────────────────
# Delegated to run-watch.sh (watch-name resolution incl. typographic-apostrophe
# folding, the watchOS build, and the devicectl install + launch). A missing or
# unreachable watch is not fatal to the iOS/mac legs — it is tallied so the run
# still exits non-zero, mirroring the unreachable-unlock device handling above.
if [[ "$RUN_WATCH" -eq 1 ]]; then
    echo ""
    echo "==> Building and launching on the Apple Watch (via run-watch.sh)…"
    if ! bash scripts/run-watch.sh; then
        echo "❌ Watch step failed (unpaired or unreachable)." >&2
        failures=$((failures + 1))
    fi
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    summary="Installed and launched on ${#DEVICES[@]} device(s)"
    [[ "$SIM_LAUNCHED" -gt 0 ]] && summary="$summary and $SIM_LAUNCHED simulator(s)"
    [[ "$RUN_MAC" -eq 1 ]] && summary="$summary and macOS"
    [[ "$RUN_WATCH" -eq 1 ]] && summary="$summary and the Apple Watch"
    echo "✅ $summary."
else
    echo "❌ $failures step(s) failed — see errors above." >&2
    exit 1
fi
