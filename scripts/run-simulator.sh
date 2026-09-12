#!/usr/bin/env bash
set -euo pipefail

# Boot, install, and launch CheckStitch on a simulator.
#
# Usage: run-simulator.sh <destination> <app-path>
#   destination  an xcodebuild destination (platform=iOS Simulator,id=… or ,name=…)
#   app-path     path to the built .app bundle
#
# The destination usually comes from the Makefile, which prefers the
# per-worktree simulator recorded in .simulator_id so parallel agents do not
# share one device.

SIM="${1:?usage: run-simulator.sh <destination> <app-path>}"
APP="${2:?usage: run-simulator.sh <destination> <app-path>}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"

cd "$(dirname "$0")/.."

# Resolve the destination to a concrete UDID.
if ! UDID="$(bash "$(dirname "$0")/resolve-sim-udid.sh" "$SIM")"; then
    exit 1
fi
if [[ ! -d "$APP" ]]; then
    echo "ERROR: app bundle not found at $APP (run 'make build' first)" >&2
    exit 1
fi

echo "==> Booting simulator ${UDID}…"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "==> Installing ${APP}…"
xcrun simctl install "$UDID" "$APP"

echo "==> Launching ${BUNDLE_ID}…"
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"

echo ""
echo "✅ Launched $BUNDLE_ID on $UDID"
