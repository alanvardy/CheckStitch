#!/bin/bash
# CheckStitch gate: build, unit + UI tests, then static checks over the shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

make build
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
