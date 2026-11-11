#!/bin/bash
set -euo pipefail

# scripts/run-watch.sh — build CheckStitchWatch for the watchOS device and
# install + launch it on the paired Apple Watch via devicectl.
#
#   ./scripts/run-watch.sh
#
# Overrides (same env-override pattern as the Makefile):
#   SCHEME=… WATCH_SCHEME=… BUNDLE_ID=… CONFIGURATION=… DERIVED_DATA=…
#   WATCH_NAME="Alan's Apple Watch"
#
# The watch device is resolved to an identifier through `devicectl list
# devices -j` — never a bare name in a build destination. The build runs
# against that device's own `id=<udid>` destination with
# `-allowProvisioningDeviceRegistration` so a freshly paired watch is
# auto-registered. If devicectl cannot reach the watch it usually reports
# usage-assertion error 4016 (device offline / Remote Device Services off);
# an unreachable watch takes the generic `.watchOS` fallback build (so a
# signing/compile failure still surfaces) and then fails the leg.

SCHEME="${SCHEME:-CheckStitch}"
WATCH_SCHEME="${WATCH_SCHEME:-CheckStitchWatch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch.watchkitapp}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"
# The apostrophe-default is held in its own variable: bash rejects a literal
# `'` inside a `${...:-...}` word even within double quotes (parse error).
DEFAULT_WATCH_NAME="Alan's Apple Watch"
WATCH_NAME="${WATCH_NAME:-$DEFAULT_WATCH_NAME}"
DEVICES_JSON="${TMPDIR:-/tmp}/run-watch-$$.json"
RESOLVER_SCRIPT="${TMPDIR:-/tmp}/run-watch-resolver-$$.py"
trap 'rm -f "$DEVICES_JSON" "$RESOLVER_SCRIPT"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCH_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-watchos/${WATCH_SCHEME}.app"

cd "$REPO_ROOT"

echo "==> Resolving ${WATCH_NAME}…"
if ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    exit 1
fi

# The Python resolver is written to its own file rather than fed to
# `python3 -` through a here-document: macOS's /bin/bash 3.2 cannot parse a
# here-document inside `$(…)` (it reports a spurious unmatched double quote),
# and the gate syntax-checks every script with `bash -n` under the system bash.
cat >"$RESOLVER_SCRIPT" <<'PY'
import json
import re
import sys
import unicodedata


def normalize_device_name(name):
    # Hardware names carry typographic apostrophes and non-breaking spaces
    # (e.g. "Alan\u2019s Apple\u00a0Watch"); fold both sides to plain ASCII so the
    # CLI's ASCII default still matches.
    name = unicodedata.normalize("NFKC", name)
    name = name.replace("\u2018", "'").replace("\u2019", "'")
    return re.sub(r"\s+", " ", name).strip().casefold()


with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

wanted = normalize_device_name(sys.argv[2])
for device in payload["result"]["devices"]:
    props = device.get("deviceProperties", {})
    if normalize_device_name(props.get("name", "")) != wanted:
        continue
    conn = device.get("connectionProperties", {}) or {}
    if conn.get("transportType") is None or conn.get("tunnelState") == "unavailable":
        print("unreachable", file=sys.stderr)
        sys.exit(2)
    print(device["identifier"])
    break
else:
    sys.exit(3)
PY

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
        echo "❌ ${WATCH_NAME} is unreachable and the fallback build produced no app at $WATCH_APP." >&2
    else
        echo "❌ ${WATCH_NAME} is unreachable — the app was built but not installed." >&2
    fi
    exit 1
fi

if [[ "$WATCH_RESOLVE_STATUS" -ne 0 ]]; then
    echo "❌ Could not resolve '${WATCH_NAME}' (unpaired or unknown)." >&2
    echo "   Pair it in Xcode → Window → Devices and Simulators, then retry." >&2
    exit 1
fi

echo "==> Building ${WATCH_SCHEME} (${CONFIGURATION}) for ${WATCH_NAME}…"
xcodebuild -scheme "$WATCH_SCHEME" \
  -destination "id=$WATCH_ID" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build

if [[ ! -d "$WATCH_APP" ]]; then
    echo "❌ Built watch app not found at $WATCH_APP" >&2
    exit 1
fi

echo "==> Installing on ${WATCH_NAME}…"
if ! xcrun devicectl device install app --device "$WATCH_ID" "$WATCH_APP"; then
    echo "❌ Install failed (is the watch unlocked and is Remote Device Services on?)." >&2
    exit 1
fi

echo "==> Launching on ${WATCH_NAME}…"
xcrun devicectl device process launch \
  --terminate-existing --activate \
  --device "$WATCH_ID" \
  "$BUNDLE_ID"

echo "✅ ${WATCH_SCHEME} installed and launched on ${WATCH_NAME}."