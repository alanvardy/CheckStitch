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
# devices -j` — never a bare name in a build destination. If devicectl cannot
# reach the watch it usually reports usage-assertion error 4016 (device
# offline / Remote Device Services off); that is reported explicitly.

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
trap 'rm -f "$DEVICES_JSON"' EXIT

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WATCH_APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-watchos/${WATCH_SCHEME}.app"

cd "$REPO_ROOT"

echo "==> Resolving ${WATCH_NAME}…"
if ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
    echo "❌ devicectl could not list devices." >&2
    exit 1
fi

WATCH_ID="$(
    python3 - "$DEVICES_JSON" "$WATCH_NAME" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as fh:
    payload = json.load(fh)

wanted = sys.argv[2]
for device in payload["result"]["devices"]:
    props = device.get("deviceProperties", {})
    if props.get("name") != wanted:
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
)" || {
    echo "❌ Could not resolve '${WATCH_NAME}' (unpaired, unreachable, or Developer Mode off)." >&2
    echo "   Unlock the watch, keep it on this Mac's Wi-Fi, then retry. devicectl error 4016 means the same." >&2
    exit 1
}

echo "==> Building ${WATCH_SCHEME} (${CONFIGURATION}) for watchOS…"
xcodebuild -scheme "$WATCH_SCHEME" \
  -destination 'generic/platform=watchOS' \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
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