# Design Discussion

## Current State

The shared gate is `scripts/test.sh` (`#!/bin/bash`, `set -euo pipefail`,
`scripts/test.sh:1-3`). It runs, in order: `make build` (:40) → simulator
lock + headless pre-boot of this worktree's UDID (:50-100) → `make test`
(:105, i.e. `test-unit` + `test-ui`, `Makefile:59`) → `make build-mac` (:111)
→ `make watch-build` (:115) → `bash scripts/tests/run.sh` (:117-119) →
shellcheck (:121-126) → `echo "gate: ok"` (:127). Failure detection is
`set -euo pipefail` only; there is no status accumulation and no per-leg
exit-code check.

**No warning enforcement exists anywhere.** Dedicated greps found zero
`SWIFT_TREAT_WARNINGS_AS_ERRORS`, `SWIFT_SUPPRESS_WARNINGS` or
`WARNING_CFLAGS` in `project.pbxproj`; `CheckStitchCore/Package.swift:1-21`
has no `swiftSettings` at all. `project.pbxproj:366-408` carries only the
standard `CLANG_WARN_*` / `GCC_WARN_*` clusters, and `GCC_WARN_ABOUT_RETURN_TYPE
= YES_ERROR` is the sole warning-related `YES_ERROR`.

**No xcodebuild output capture exists.** Every leg — gate, Makefile recipes
(`Makefile:18-21, 31-35, 41-45, 51-53, 65-73, 76-83`), and CI — streams
straight to the console; the only redirects are `2>/dev/null` on auxiliary
probes. CI (`.github/workflows/dependabot-checks.yml:49-74`) runs the make
legs as separate steps and never invokes `scripts/test.sh` itself.

**Current warning inventory** (from `large.md` recon runs; corrected by
`research.md` where the recon double-counted):

| Leg | Warnings |
|---|---|
| `make build-mac` | 2× trailing-closure confusion, 2× unused `refresh()` result, 1× AppIntents metadata |
| `make build` | same two source kinds, plus AppIntents metadata |
| `make test-unit` | 4× redundant `#require(_:_:)` (`WatchChecklistStoreTests.swift:59,142,158,183`), 4× unused immutable value (`ChecklistImportSessionTests.swift:82,88`; `ChecklistStoreTests.swift:1295,1296`), plus metadata |
| `make watch-build` | AppIntents metadata only — watch sources clean |
| `make test-ui` | **unverified** — `CheckStitchUITests` compiles only here |

The only app-source discard-result site is `CheckStitch/ContentView.swift:100`
`.refreshable { await syncService.refresh() }`, whose callee
`CheckStitch/ChecklistSyncService.swift:77` returns a non-void `SyncOutcome`.
`ChecklistStore.swift` has no `refresh()` — the recon's attribution there is
not reproducible. Trailing-closure candidates are shape-inferred:
`ContentView.swift:104,182,215` (empty `Button("OK", role: .cancel) {}`
closures inside `.alert(...)`) and `ChecklistStore.swift:353,371,259`.

Two non-source "warning" sources must not be mistaken for diagnostics: the
gate's own hand-written `echo "warning: ..."` lines
(`scripts/test.sh:65,102,124`) and the toolchain's AppIntents metadata note
("Metadata extraction skipped, no AppIntents.framework dependency found"),
which appears in 3 of 4 legs, has no literal anywhere in repo files, and has
been counted up to 11× per full gate.

The shell harness `scripts/tests/run.sh` is the existing mechanism for
testing gate behaviour: `new_stubs` (:22-35) writes PATH-inserted stubs for
`xcrun`, `make`, `defaults`, `open`, `osascript`, `xcodebuild` that log argv
to `$STUB_ROOT/<name>.log`, and cases assert on those argv logs
(:101-123, :205-252, :254-302). It runs under a private `TMPDIR` for lock
tests (:132-174) and already asserts pbxproj content via awk (:307-330).

## Desired End State

The gate fails whenever a compiler warning is produced by any of its five
xcodebuild legs, and passes clean (`gate: ok`) only when none is. Concretely:

1. Each Makefile leg that compiles Swift (build, test-unit, test-ui,
   build-mac, watch-build) passes warnings-as-errors build settings.
2. Every warning currently produced by app sources and test suites is
   eliminated at source, so the gate is green with enforcement on.
3. The AppIntents metadata note is out of scope by construction — it is a
   build-phase message, not a Swift/clang diagnostic, so it is neither
   flagged nor allowlisted.
4. The gate's own `warning:` messages and shellcheck behaviour are unchanged.
5. A harness case asserts the flag reaches every leg, so enforcement cannot
   be silently deleted.

Verification: `./scripts/test.sh` prints `gate: ok` with the flags present,
and a deliberate warning in any Swift source (manual check, reverted) makes
the corresponding leg fail.

## Patterns to Follow

- **Makefile leg shape**: each leg is one `xcodebuild` recipe with a
  destination, `-configuration $(CONFIGURATION)` and shared
  `-derivedDataPath $(DERIVED_DATA)` (`Makefile:18-21, 45-53`). Shared knobs
  are declared as top-of-file variables (`SCHEME`, `WATCH_SCHEME`,
  `CONFIGURATION`, `DERIVED_DATA`, `Makefile:4-8`) — the new warning setting
  belongs there, referenced by each recipe, not pasted per leg.
- **Harness argv assertions**: stubs log argv, cases assert on the log
  (`scripts/tests/run.sh:101-123`). The enforcement test follows this shape
  exactly, and inherits the `GATE_TESTS_SKIP=1` + stubbed-`make` discipline
  so no real build is triggered.
- **Gate hygiene**: `set -euo pipefail`, tolerate-and-continue only where
  explicitly justified (`|| true` at `scripts/test.sh:12,77-78,89,95,99`),
  and never leave a bare `name=` destination in a script (`AGENTS.md`).
- **Determinism**: serial testables (`parallelizable="NO"`,
  `CheckStitch.xcscheme` TestAction :26-59) and per-suite `-only-testing:`
  pins (`Makefile:45-67`) — the check must not add parallelism or reorder
  legs.
- **Swift Testing idiom**: `try #require(<optional|throwing>)` bound to a
  `let` is the repo-wide unwrap-or-fail pattern (e.g.
  `LocalizationTests.swift:15,25,47`; `ChecklistSyncServiceTests.swift:144,183`)
  and should keep being used for genuinely optional values.

**Patterns NOT to follow:**

- Do **not** add `SWIFT_TREAT_WARNINGS_AS_ERRORS` to `project.pbxproj` test
  targets: they deliberately omit shared build settings so suites opt in with
  `@MainActor` (`conventions.md`); the shared scheme/pbxproj config is also
  asserted by the harness awk check (`scripts/tests/run.sh:307-330`).
- Do **not** grep gate console output for the string `warning` — the gate's
  own three `echo "warning: ..."` lines and the AppIntents note both
  false-positive, and no capture infrastructure exists to scope them.
- Do **not** silence warnings with `@discardableResult` on unrelated Core
  API, `#warning`-adjacent pragmas, or `-suppress-warnings`; fix the site.
- Do **not** swallow a failing leg with `|| true` to keep the gate green.

## Design Decisions

1. **Detection mechanism**: warnings-as-errors compiler flags — chosen over
   log capture + grep. It is compiler-native, needs no parsing, cannot
   false-positive on the gate's own `warning:` lines or toolchain notes, and
   fails at the exact diagnostic. Grep-based capture would require new log
   plumbing and an allowlist coupled to a toolchain string.

2. **Where the flag lives**: a single shared Makefile variable (e.g.
   `WARNINGS_AS_ERRORS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
   GCC_TREAT_WARNINGS_AS_ERRORS=YES`) applied in each compiling recipe —
   `build`, `test-unit`, `test-ui` (both `build-for-testing` and
   `test-without-building` as appropriate), `build-mac`, `watch-build`. The
   gate and CI both inherit it automatically; local Xcode builds and the
   pbxproj are untouched. `build-mac-signed`, `run-watch.sh:83` and
   `run-devices.sh:124` are device-deployment helpers outside the gate and are
   left unchanged — the sources they compile are identical and will already be
   warning-free.

3. **AppIntents noise**: ignored by construction. The metadata note is emitted
   by the `ExtractAppIntentsMetadata` build phase, not by the Swift or clang
   compiler, so warnings-as-errors never observes it. No allowlist, no
   suppression setting, no build-phase disabling.

4. **Gate's own `warning:` lines**: kept verbatim (`scripts/test.sh:65,102,124`).
   With a non-grep mechanism they cannot collide, and they carry real signal
   about degraded runs (lock contention, missing simulator id, absent
   shellcheck).

5. **Regression test for enforcement**: a new `scripts/tests/run.sh` case that
   drives the stubbed `xcodebuild` through the real Makefile recipes (or
   asserts the recipes' argv) and fails if the warnings-as-errors setting is
   absent from any compiling leg. This matches the existing argv-assertion
   style and needs no compiler.

6. **Source fixes — app target**: fix at the call site with the minimal
   semantic-preserving edit. For `ContentView.swift:100`, discard explicitly
   (`_ = await syncService.refresh()`) rather than changing `refresh()`'s API
   contract in Core. For the trailing-closure warnings, disambiguate the
   closure boundary at whichever sites the compiler actually flags
   (`ContentView.swift:104,182,215`; `ChecklistStore.swift:353,371,259`) —
   exact attribution to be confirmed by a real leg run, since compiler output
   is not committed.

7. **Source fixes — test suites**: replace the four redundant
   `let runID = try #require(store.run(checklist))` bindings
   (`WatchChecklistStoreTests.swift:59,142,158,183`) with plain `let runID =
   store.run(checklist)`, since `WatchChecklistStore.run()` returns a
   non-optional `UUID` (`CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift:281-282`).
   For the four unused bindings (`ChecklistImportSessionTests.swift:82,88`;
   `ChecklistStoreTests.swift:1295,1296`): delete bindings that were only
   documentary, and use `_ = try ...` where the call itself is the setup
   under test. Genuine `#require` uses (e.g.
   `WatchChecklistStoreTests.swift:230`, and the rest of the repo) stay.

8. **Scope of enforcement**: only the five gate legs. Device/signed helpers
   (`build-mac-signed`, `run-watch.sh`, `run-devices.sh`) are out of scope —
   adding `-allowProvisioningUpdates`-style flags there changes deployment
   ergonomics for no gate benefit.

9. **CI**: no workflow edit required. `dependabot-checks.yml` invokes the same
   Makefile legs, so it inherits enforcement by construction.

## What We're NOT Doing

- No log-capture / grep-based warning scanner, and no new log files in the
  gate.
- No edits to `project.pbxproj` or `CheckStitchCore/Package.swift` build
  settings.
- No AppIntents suppression flag or allowlist.
- No change to the gate's leg order, lock/pre-boot logic, or its own
  `warning:` messages.
- No new test framework or fixture-compilation leg; the harness argv
  assertion is the guard.
- No enforcement in `run-watch.sh` / `run-devices.sh` / `build-mac-signed`.
- No unrelated refactors of `ChecklistStore`, `ChecklistSyncService`, or the
  test suites beyond the warning sites.

## Open Risks

- **Trailing-closure attribution is inferred, not observed.** The exact
  `file:line` set that fires is unknown until a real leg runs. Mitigation: the
  plan's first step is a real `make build-mac` / `make build` run with
  warnings-as-errors on, which turns the guess into a definitive list.
- **`CheckStitchUITests` warning count is unverified.** It compiles only under
  `make test-ui`; enforcement will surface anything there, and it may add
  unexpected fix sites.
- **Incremental builds can hide warnings.** Legs share `DerivedData`, so a
  cached compile skips unchanged files and warnings-as-errors fires only for
  files actually recompiled — a local gate could pass spuriously. CI runs on a
  fresh checkout and is the authoritative backstop; a full clean is not added
  to the gate to avoid a large runtime cost.
- **Command-line build-setting overrides and SPM targets.** `CheckStitchCore`
  is built as a package dependency; whether the Makefile override propagates
  into its targets needs confirming during implementation (the package
  currently has no warnings, so the risk is low).
- **Harness argv assertion durability.** If the Makefile recipe shape changes
  (e.g. flags moved to an xcconfig), the harness case must move with it.
