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
#
# The app is seeded with a test-data fixture by default so every launch has
# checklists to click through. Seeding flips the app into its `--ui-testing`
# mode (ephemeral UserDefaults suite, sync/purchases off), so the real App
# Group is never touched. Overrides:
#   SEED=0             launch unseeded
#   SEED_FILE=<path>   use another ChecklistEnvelope JSON (default
#                      scripts/fixtures/dev-seed.json)

SIM="${1:?usage: run-simulator.sh <destination> <app-path>}"
APP="${2:?usage: run-simulator.sh <destination> <app-path>}"
BUNDLE_ID="${BUNDLE_ID:-app.alanvardy.CheckStitch}"
SEED="${SEED:-1}"
SEED_FILE="${SEED_FILE:-scripts/fixtures/dev-seed.json}"

# shellcheck source=scripts/sim-window.sh
source "$(dirname "$0")/sim-window.sh"

cd "$(dirname "$0")/.."

# Resolve the seed path now that we are at the repo root, and hand it to the
# launched app through simctl's SIMCTL_CHILD_ environment bridge.
if [[ "$SEED" != "0" ]]; then
    case "$SEED_FILE" in
        /*) ;;
        *) SEED_FILE="$PWD/$SEED_FILE" ;;
    esac
    if [[ ! -f "$SEED_FILE" ]]; then
        echo "ERROR: seed file not found at $SEED_FILE (SEED=0 to launch unseeded)" >&2
        exit 1
    fi
    export SIMCTL_CHILD_CHECKSTITCH_UITEST_SEED="$SEED_FILE"
fi

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

echo "==> Showing the simulator window for ${UDID}…"
show_sim_window "$UDID"

echo "==> Installing ${APP}…"
xcrun simctl install "$UDID" "$APP"

echo "==> Launching ${BUNDLE_ID}…"
if [[ "$SEED" != "0" ]]; then
    echo "    (seeded with $SEED_FILE)"
fi
xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE_ID"

echo ""
echo "✅ Launched $BUNDLE_ID on $UDID"
