#!/bin/bash
# CheckStitch gate: there is no test target, so the gate is a simulator build
# plus static checks over the repo's shell scripts.
set -euo pipefail

cd "$(dirname "$0")/.."

make build

if command -v shellcheck >/dev/null 2>&1; then
  shellcheck scripts/*.sh
else
  echo "warning: shellcheck not installed — skipping script lint" >&2
  for f in scripts/*.sh; do bash -n "$f"; done
fi

echo "gate: ok"
