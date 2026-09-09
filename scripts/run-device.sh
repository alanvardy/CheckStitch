#!/bin/bash
set -euo pipefail

# === Configuration (overridable) ===
SCHEME="${SCHEME:-CheckStitch}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"
CONFIGURATION="${CONFIGURATION:-Debug}"
DERIVED_DATA="${DERIVED_DATA:-DerivedData}"

# === Derived paths ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_PATH="${DERIVED_DATA}/Build/Products/${CONFIGURATION}-iphoneos/${SCHEME}.app"

# === Temp file + cleanup (use the OS temp dir; do not clobber $TMPDIR) ===
DEVICES_JSON="${TMPDIR:-/tmp}/run-device-$$.json"
trap 'rm -f "$DEVICES_JSON"' EXIT

cd "$REPO_ROOT"

# === Build ===
echo "==> Building $SCHEME for iOS device..."
xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  -allowProvisioningUpdates \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: App bundle not found at $APP_PATH" >&2
  exit 1
fi

# === Discover device ===
echo "==> Discovering iOS device..."
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required (brew install jq)." >&2; exit 1; }

if ! xcrun devicectl list devices -j "$DEVICES_JSON" >/dev/null 2>&1; then
  echo "ERROR: devicectl could not list devices." >&2
  echo "       Plug in the device, unlock it, and tap Trust, then retry." >&2
  exit 1
fi

# devicectl nests devices under `result.devices`, with platform/deviceType under
# hardwareProperties and name/developerModeStatus under deviceProperties. A
# reachable physical device has a non-null transportType and not "unavailable".
# Prefer an iPhone over an iPad (the ticket's target is the iPhone).
DEVICE_ID=$(jq -re '
  [
    .result.devices[]
    | select(.hardwareProperties.platform == "iOS")
    | select(.hardwareProperties.deviceType == "iPhone" or .hardwareProperties.deviceType == "iPad")
    | select(.deviceProperties.developerModeStatus == "enabled")
    | select((.connectionProperties.transportType | type) == "string")
    | select(.connectionProperties.tunnelState != "unavailable")
  ]
  | sort_by(.hardwareProperties.deviceType != "iPhone")
  | .[0].identifier
' "$DEVICES_JSON") || DEVICE_ID=""

if [ -z "$DEVICE_ID" ]; then
  echo "ERROR: No iOS device with Developer Mode enabled and reachable." >&2
  echo "       Ensure the device is unlocked, on Wi-Fi, and Developer Mode is on." >&2
  exit 1
fi

DEVICE_NAME=$(jq -r --arg id "$DEVICE_ID" '
  .result.devices[] | select(.identifier == $id) | .deviceProperties.name
' "$DEVICES_JSON")
echo "   Device: $DEVICE_NAME ($DEVICE_ID)"

# === Install ===
echo "==> Installing $SCHEME.app..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

# === Launch ===
echo "==> Launching $BUNDLE_ID..."
xcrun devicectl device process launch \
  --terminate-existing \
  --activate \
  --device "$DEVICE_ID" \
  "$BUNDLE_ID"

echo ""
echo "✅ Installed and launched $SCHEME on $DEVICE_NAME"
