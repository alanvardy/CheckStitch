#!/bin/bash
# Resolve an xcodebuild iOS Simulator destination to a concrete UDID.
#
# Usage: resolve-sim-udid.sh [--require-id] <destination>
#   --require-id  fail unless the destination is already pinned with ',id='
#                 (used by the gate so it never prepares a shared device)
set -euo pipefail

require_id=0
if [[ "${1:-}" == "--require-id" ]]; then
    require_id=1
    shift
fi
SIM="${1:?usage: resolve-sim-udid.sh [--require-id] <destination>}"

if [[ "$SIM" == *",id="* ]]; then
    UDID="${SIM##*id=}"
else
    if [[ "$require_id" -eq 1 ]]; then
        echo "ERROR: destination '$SIM' is not pinned to a simulator (expected ',id=')" >&2
        exit 1
    fi
    NAME="${SIM##*name=}"
    NAME="${NAME%%,*}"
    UDID="$(xcrun simctl list devices available \
        | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')" || true
fi

if [[ -z "$UDID" ]]; then
    echo "ERROR: could not resolve a simulator for '$SIM'" >&2
    exit 1
fi

# A pinned destination must name a real UDID (this is what keeps the gate off
# shared devices); a corrupt .simulator_id would otherwise reach simctl raw.
if [[ "$require_id" -eq 1 && ! "$UDID" =~ ^[A-Fa-f0-9]{8}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{4}-[A-Fa-f0-9]{12}$ ]]; then
    echo "ERROR: '$UDID' is not a valid simulator UDID" >&2
    exit 1
fi

printf '%s\n' "$UDID"
