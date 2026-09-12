#!/bin/bash
# CheckStitch gate: build, unit + UI tests, then static checks over the shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

SIM_ID_FILE="${SIM_ID_FILE:-.simulator_id}"
GATE_UDID=""

# Resolve this worktree's own simulator, if it has one. Absent .simulator_id
# degrades to the Makefile's shared name= fallback: skip pre-boot entirely
# rather than ever touching a shared device.
GATE_DEST=""
if [[ -n "${SIM:-}" ]]; then
  GATE_DEST="$SIM"
elif [[ -f "$SIM_ID_FILE" ]]; then
  GATE_DEST="platform=iOS Simulator,id=$(cat "$SIM_ID_FILE")"
fi
if [[ -n "$GATE_DEST" ]]; then
  GATE_UDID="$(bash scripts/resolve-sim-udid.sh --require-id "$GATE_DEST" 2>/dev/null || true)"
fi

make build

# Phase 4b substitution (phase-1 spike proved AutoOpenDevice ineffective on
# Xcode 26.6): a bounded host-scoped lock serializes the window-touching part
# of the gate across concurrent gates, and Simulator.app is quit so no window
# attaches to the device the gate pre-boots. The lock degrades to a warning
# after LOCK_TIMEOUT seconds — it never blocks past that.
LOCK_DIR="${TMPDIR:-/tmp}/checkstitch-simulator.lock"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-60}"
LOCK_HELD=0

acquire_lock() {
  local waited=0
  while ! mkdir "$LOCK_DIR" 2>/dev/null; do
    if [[ $waited -ge $LOCK_TIMEOUT ]]; then
      echo "warning: simulator lock busy after ${LOCK_TIMEOUT}s — running without it" >&2
      return 0
    fi
    sleep 1
    waited=$((waited + 1))
  done
  LOCK_HELD=1
}

release_lock() {
  [[ "${LOCK_HELD:-0}" == "1" ]] && rmdir "$LOCK_DIR" 2>/dev/null || true
}

# ONE EXIT trap only: bash replaces a previous `trap … EXIT`, so the lock
# release and the scoped UDID shutdown must share a single handler. The
# shutdown never targets all/booted — only the resolved gate UDID.
gate_cleanup() {
  release_lock
  if [[ -n "$GATE_UDID" ]]; then
    xcrun simctl shutdown "$GATE_UDID" 2>/dev/null || true
  fi
}

acquire_lock
trap 'gate_cleanup' EXIT
osascript -e 'tell application "Simulator" to quit' 2>/dev/null || true

if [[ -n "$GATE_UDID" ]]; then
  echo "==> Pre-booting gate simulator ${GATE_UDID}…"
  xcrun simctl boot "$GATE_UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$GATE_UDID" -b
else
  echo "warning: no worktree simulator id — skipping pre-boot and shutdown" >&2
fi

make test

# `make build` only compiles for the iOS Simulator; the macOS slice is the
# same sources against a different platform, so build it here too — otherwise
# iOS-only API compiles green in the gate and only breaks in run-devices.sh.
make build-mac

if [[ "${GATE_TESTS_SKIP:-}" != "1" ]]; then
  bash scripts/tests/run.sh
fi

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh scripts/tests/*.sh
else
  echo "warning: shellcheck not installed — skipping script lint" >&2
  for f in scripts/*.sh scripts/tests/*.sh; do bash -n "$f"; done
fi

echo "gate: ok"