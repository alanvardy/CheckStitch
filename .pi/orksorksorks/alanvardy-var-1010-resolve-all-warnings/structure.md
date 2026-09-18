# Structure Outline

## Approach

Ride warnings-as-errors in one shared Makefile variable, applied **one compiling
leg at a time** (`build-mac` → `build` → `test-unit` → `test-ui` / `watch-build`),
fixing each leg's source warnings as its flag is switched on. Every slice leaves
`./scripts/test.sh` green and the tree clean; a shell-harness argv assertion pins
the flag so enforcement cannot be silently deleted. `scripts/test.sh` itself is
unchanged — it inherits enforcement from the Makefile legs, and its own three
`warning:` lines and the AppIntents metadata note are out of scope by
construction. Turning the flag on per leg (not all five at once) is what keeps
each phase a green, vertical increment; no horizontal "big-bang" phase is needed.

---

## Phase 1: Walking skeleton — macOS leg enforced end to end

`make build-mac` now fails on any Swift/clang warning, and the app-source warning
kinds it surfaces are fixed at source. Demonstrable: `make build-mac` is
warning-free, and injecting a warning fails the leg.

**Files**: `Makefile`, `CheckStitch/ContentView.swift`, `scripts/tests/run.sh`
(plus whichever trailing-closure sites the leg actually reports —
`ChecklistStore.swift:353,371,259` are shape-inferred candidates only).

**Key changes**:
- `WARNINGS_AS_ERRORS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES` — new top-of-file Makefile variable beside `CONFIGURATION`/`DERIVED_DATA`.
- `build-mac` recipe gains a trailing `$(WARNINGS_AS_ERRORS)` build-setting argument.
- `ContentView.swift:100` — `.refreshable { _ = await syncService.refresh() }` (discard explicitly; `refresh()`'s `SyncOutcome` API unchanged).
- Trailing-closure disambiguation at the exact `file:line` set the leg reports.

**Contract**: the variable name `WARNINGS_AS_ERRORS`, the additive per-leg recipe
argument, and the harness case name `warnings_as_errors_reaches_compiling_legs`
(initially asserting `build-mac` only). Later slices *append* their leg to the
list — never redefine the variable or the case.

**Tests**: harness case `warnings_as_errors_reaches_compiling_legs` — run the real
`make build-mac` with a stubbed `xcodebuild`, asserting both
`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES` and `GCC_TREAT_WARNINGS_AS_ERRORS=YES` appear
in `$STUB_ROOT/xcodebuild.log`. Sad path: strip the flag from the recipe and
confirm the case fails.
**Verify**: `bash scripts/tests/run.sh` green; `make build-mac` clean; manual
deliberate-warning inject → `make build-mac` fails → revert. `make build-mac-signed`
untouched.

---

## Phase 2: iOS simulator build leg enforced

`make build` fails on any warning; any iOS-only app-source sites (beyond Phase 1's)
are fixed. Demonstrable: the iOS app target is warning-free under enforcement.

**Files**: `Makefile`, `CheckStitch/*.swift` (iOS-only sites, if any),
`scripts/tests/run.sh`.

**Key changes**:
- `build` recipe gains `$(WARNINGS_AS_ERRORS)`.
- Harness leg list extended to `build`.

**Contract**: same variable; harness case now covers `build-mac` + `build`.

**Tests**: harness assertion extended; `make build` clean; deliberate-warning sad
path.
**Verify**: `make build`; `bash scripts/tests/run.sh`.

---

## Phase 3: Unit-test leg enforced

`make test-unit` fails on any warning; the 4 redundant `#require` and 4
unused-immutable-value warnings are fixed.

**Files**: `Makefile`, `CheckStitchTests/WatchChecklistStoreTests.swift`,
`CheckStitchTests/ChecklistImportSessionTests.swift`,
`CheckStitchTests/ChecklistStoreTests.swift`, `scripts/tests/run.sh`.

**Key changes**:
- `test-unit` recipe gains `$(WARNINGS_AS_ERRORS)`.
- `WatchChecklistStoreTests.swift:59,142,158,183` — `let runID = store.run(checklist)` (drop `try #require`; callee returns a non-optional `UUID`).
- `ChecklistImportSessionTests.swift:82,88` — remove the documentary `let v1`/`let v2`; `_ = try session.prepare(...)` where the call is the setup under test.
- `ChecklistStoreTests.swift:1295-1296` — `_ = store.create(...)` for the unreferenced bindings.
- Genuine `#require` sites (e.g. `WatchChecklistStoreTests.swift:230`) untouched.

**Contract**: harness case covers `test-unit` too; no change to
`WatchChecklistStore.run()`'s API.

**Tests**: harness assertion extended; `make test-unit` clean and green;
deliberate-warning sad path.
**Verify**: `make test-unit`; `bash scripts/tests/run.sh`.

---

## Phase 4: UI-test and watch legs enforced

`make test-ui` and `make watch-build` fail on any warning; the previously
unverified `CheckStitchUITests` target is fixed if it emits anything.

**Files**: `Makefile`, `CheckStitchUITests/CheckStitchUITests.swift` (only if
flagged), `scripts/tests/run.sh`.

**Key changes**:
- `test-ui` — flag on the compiling `build-for-testing` invocation (and `test-without-building` for uniformity; harmless).
- `watch-build` recipe gains `$(WARNINGS_AS_ERRORS)`.
- Harness leg list extended to `test-ui` (both `xcodebuild` calls) and `watch-build`.

**Contract**: all five gate legs now carry the variable; the harness case is
complete.

**Tests**: harness assertion extended; `make test-ui` + `make watch-build` clean;
deliberate-warning sad path on each.
**Verify**: `make test-ui`; `make watch-build`; `bash scripts/tests/run.sh`.

---

## Phase 5: Hardening — full-gate confidence and docs

The complete `./scripts/test.sh` runs green with enforcement on every leg, CI
inherits it, and the regression guard is documented so it survives recipe
refactors.

**Files**: `scripts/tests/run.sh`, `Makefile` (comment on the variable),
`AGENTS.md` (one line: gate builds treat warnings as errors).

**Key changes**: harness case asserts all five legs from one place; a comment
names the contract; confirm `dependabot-checks.yml` needs no edit (it invokes the
same make legs).

**Tests**: full harness green; `./scripts/test.sh` prints `gate: ok` with flags
present; a deliberate warning in a Swift source fails the corresponding leg
(manual, reverted). Record the known limitation: incremental `DerivedData` can
skip recompiles, so CI on a fresh checkout is the authoritative backstop.
**Verify**: `./scripts/test.sh` → `gate: ok`; `bash scripts/tests/run.sh`.

---

## Testing Checkpoints

- After Phase 1: `make build-mac` warning-free with the flag on; harness `build-mac` assertion green.
- After Phase 2: `make build` warning-free; harness covers `build`.
- After Phase 3: `make test-unit` warning-free and green; harness covers `test-unit`.
- After Phase 4: `make test-ui` + `make watch-build` warning-free; harness covers all five legs.
- After Phase 5: `./scripts/test.sh` → `gate: ok`; a deliberate warning fails its leg.
