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

# === Temp dir + cleanup ===
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

cd "$REPO_ROOT"

# === Build ===
echo "==> Building $SCHEME for iOS device..."
xcodebuild -scheme "$SCHEME" \
  -destination 'generic/platform=iOS' \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  build

if [ ! -d "$APP_PATH" ]; then
  echo "ERROR: App bundle not found at $APP_PATH" >&2
  exit 1
fi

# === Discover device ===
echo "==> Discovering iOS device..."
DEVICES_JSON="$TMPDIR/devices.json"
xcrun devicectl list devices -j > "$DEVICES_JSON"

# jq filter: platform=iOS, developerModeStatus=enabled, reachable
DEVICE_ID=$(jq -r '
  .devices[]
  | select(.platform == "iOS")
  | select(.developerModeStatus == "enabled")
  | select(
      (.connectionProperties.reachable == true) or
      (.connectionProperties.tunnelState == "connected")
    )
  | .identifier
' "$DEVICES_JSON" | head -n1)

if [ -z "$DEVICE_ID" ]; then
  echo "ERROR: No iOS device with Developer Mode enabled and reachable." >&2
  echo "       Ensure the device is unlocked, on Wi-Fi, and Developer Mode is on." >&2
  exit 1
fi

DEVICE_NAME=$(jq -r --arg id "$DEVICE_ID" '
  .devices[] | select(.identifier == $id) | .name
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
