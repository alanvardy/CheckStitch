# Task

Make the repo's gate enforce a clean build: add a warnings check to
`scripts/test.sh` so the gate fails on compiler warnings, then resolve all
existing compiler warnings across every build leg (iOS simulator app build,
macOS slice, watchOS target, unit and UI test targets).

## Why LARGE

CONVENTION_RISK + MULTI_MODULE: the change rewrites the repo's shared
build/CI gate (`scripts/test.sh` + `Makefile`) — a convention every future
PR/worktree inherits — and spans the app target (CheckStitch/ContentView.swift,
CheckStitch/ChecklistStore.swift), the unit-test suites (ChecklistStoreTests,
WatchChecklistStoreTests, ChecklistImportSessionTests), the UI-test target, and
the gate itself, with a genuine check-design decision: per-leg instrumentation
vs a log grep, and how to scope out toolchain noise (an AppIntents "Metadata
extraction skipped, no AppIntents.framework dependency found" warning appears
in 3 of the 4 build legs and the gate's own `echo "warning: …"` lines would
false-positive a naive grep).

## Recon findings (warning inventory, from running the legs)

- `make build-mac` (macOS slice): 4 warnings — 2× "trailing closure in this
  context is confusable with the body of the statement" (ContentView.swift,
  ChecklistStore.swift), 2× "result of call to 'refresh()' is unused
  [#NoUsage]" (same two files), 1× AppIntents metadata noise.
- `make build` (iOS sim): 5 warnings — same 2 source kinds plus the metadata
  noise.
- `make test-unit` (CheckStitchTests, macOS): 19 warnings — 8× redundant
  '#require(_:_:)' (macro-produced), 8× unused immutable-value initialization
  (v1/v2/travel/hardware/created), across 3 suites, plus metadata noise.
- `make watch-build`: 1 warning — metadata noise only; watch app source is
  clean.
- Not yet verified: CheckStitchUITests target (compiles only under
  `make test-ui` build-for-testing) — may hold further warnings.
- Draft PR #61 on this branch contains only the scaffold commit; no prior
  work to salvage.

## Key files

- `scripts/test.sh` — gate; currently `set -euo pipefail`, runs
  make build → make test → make build-mac → make watch-build →
  scripts/tests/run.sh → shellcheck; emits its own `warning:` echo lines.
- `Makefile` — the 5 xcodebuild legs (build, test-unit, test-ui,
  build-mac, watch-build); the natural injection point for
  warning-as-error flags or per-leg log capture.
- CheckStitch/ContentView.swift, CheckStitch/ChecklistStore.swift —
  the only app-source files with warnings.
- CheckStitchTests/ChecklistStoreTests.swift,
  CheckStitchTests/WatchChecklistStoreTests.swift,
  CheckStitchTests/ChecklistImportSessionTests.swift — the test-suite
  warnings (#require redundancy, unused locals).