#!/bin/bash
# CheckStitch gate: build, unit + UI tests, then static checks over the shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

make build
make test

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  echo "warning: shellcheck not installed — skipping script lint" >&2
  for f in scripts/*.sh; do bash -n "$f"; done
fi

echo "gate: ok"
