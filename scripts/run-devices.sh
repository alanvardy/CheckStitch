#!/bin/bash
set -euo pipefail

# scripts/run-devices.sh — build CheckStitch for iOS, install + launch it on
# every paired physical iPhone/iPad (simulators excluded; Developer Mode off is
# noted, not skipped) (via devicectl), plus (by default) the host Mac and the
# paired Apple Watch (via the run-watch.sh leg).
#
#   ./scripts/run-devices.sh
#
# Overrides (same env-override pattern as the Makefile):
#   SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
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

# === Configuration (overridable) ===
SCHEME="${SCHEME:-CheckStitch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
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

cd "$REPO_ROOT"

# ── Discover devices ─────────────────────────────────────────────────────────
echo "==> Discovering paired iPhone/iPad devices…"
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
done < <(python3 - "$DEVICES_JSON" "$UNREACHABLE_LOG" <<'PY'
import json
import sys

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
        # device but is not a devicectl install target, so exclude it here the
        # same way the watch filter does.
        if hardware.get("reality") != "physical":
            continue
        name = props.get("name", "unknown device")
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
    if [[ "$RUN_MAC" -eq 1 ]]; then
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
        echo "❌ Watch step failed (unpaired, unreachable, or Developer Mode off)." >&2
        failures=$((failures + 1))
    fi
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
    summary="Installed and launched on ${#DEVICES[@]} device(s)"
    [[ "$RUN_MAC" -eq 1 ]] && summary="$summary and macOS"
    [[ "$RUN_WATCH" -eq 1 ]] && summary="$summary and the Apple Watch"
    echo "✅ $summary."
else
    echo "❌ $failures step(s) failed — see errors above." >&2
    exit 1
fi
