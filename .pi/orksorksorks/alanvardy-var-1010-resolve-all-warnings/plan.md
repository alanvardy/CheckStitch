# Implementation Plan

## Overview

Every gate leg that compiles Swift (`build-mac`, `build`, `test-unit`, `test-ui`,
`watch-build`) passes `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
GCC_TREAT_WARNINGS_AS_ERRORS=YES` from one shared Makefile variable, and every
warning those legs currently emit is fixed at source, so `./scripts/test.sh`
prints `gate: ok` only when no compiler warning was produced. A shell-harness
case drives the real Makefile with a stubbed `xcodebuild` and asserts the flags
reach each leg's argv, so enforcement cannot be silently deleted.

## Discovered facts (validated on this checkout, Xcode 27.0 / 27A266a)

These were established by running all five legs with a **fresh DerivedData** and
warnings-as-errors **off** (so every warning prints in one pass), then
re-running with the flags on after applying the fixes. They supersede the
inferred attributions in `research.md`/`design.md`/`structure.md` — see
"Deviations from structure.md".

**Definitive warning inventory — exactly 11 source sites:**

| Leg | Sites |
|---|---|
| `make build-mac` | `CheckStitch/ChecklistStore.swift:226:32` — *trailing closure in this context is confusable with the body of the statement*; `CheckStitch/ContentView.swift:100:50` — *result of call to 'refresh()' is unused* |
| `make build` (iOS sim) | same two sites |
| `make test-unit` | `CheckStitchTests/WatchChecklistStoreTests.swift:59,142,158,183` — *'#require(_:_:)' is redundant*; `CheckStitchTests/ChecklistImportSessionTests.swift:82,88` — *initialization of immutable value 'v1'/'v2' was never used*; `CheckStitchTests/ChecklistStoreTests.swift:1295,1296,1456` — *initialization of immutable value 'hardware'/'travel'/'created' was never used* |
| `make test-ui` (`build-for-testing`) | the **same 9 test-target sites** (the scheme's `build-for-testing` compiles `CheckStitchTests` for the simulator as well as `CheckStitchUITests`); `CheckStitchUITests/CheckStitchUITests.swift` itself emits nothing |
| `make watch-build` | none |

**Validated facts that shape the plan:**

- The trailing-closure warning is at `ChecklistStore.swift:226`, **not** the
  research's `:353`/`:371`/`:259`, and there is exactly **one**, not two.
- `ChecklistStoreTests.swift:1456` *does* have an unused `created` binding;
  `research.md` claimed it did not exist.
- There is **no** trailing-closure warning in `ContentView.swift:104/182/215`.
- `CheckStitchUITests.swift` is clean — the unverified risk is resolved.
- The AppIntents metadata note is present in 3 legs but never trips
  warnings-as-errors (it is an `ExtractAppIntentsMetadata` build-phase message,
  not a compiler diagnostic). Confirmed by a flags-on run that passed.
- The command-line build-setting override **does** propagate into the
  `CheckStitchCore` SPM package targets: a probe warning injected into
  `CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift` failed
  the macOS leg with the flags on (probe reverted).
- The harness-case mechanics were validated end to end: with a flag-bearing
  Makefile copy and a stubbed `xcodebuild`, all five legs logged both flags
  (`build-mac` 1 call, `build` 1, `test-unit` 1, `test-ui` 2, `watch-build` 1),
  and stripping the flag made the assertion fail.
- With the flags on and all 11 fixes applied: the macOS leg exits 0 with zero
  warnings, and `-only-testing:CheckStitchTests test` exits 0 with
  `TEST SUCCEEDED` and zero warnings.

---

## Phase 1: Walking skeleton — macOS leg enforced end to end

`make build-mac` fails on any Swift/clang warning, and the two app-source
warnings it surfaces are fixed at source. Demonstrable: `make build-mac` is
warning-free, the harness pins the flag, and injecting a warning fails the leg.

### Changes

#### 1. Shared flag variable

**File**: `Makefile`
**Action**: modify

Declare the variable beside the other shared knobs (after
`DERIVED_DATA := DerivedData`). This is the single source of truth every later
phase reuses — never redefine it.

```makefile
DERIVED_DATA := DerivedData
# Gate legs compile with warnings as errors: a compiler warning fails the leg.
# scripts/test.sh and CI inherit this through the make recipes; local Xcode
# builds and project.pbxproj are untouched. `build-mac-signed`,
# run-watch.sh and run-devices.sh are device helpers and deliberately excluded.
WARNINGS_AS_ERRORS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
```

#### 2. `build-mac` recipe

**File**: `Makefile`
**Action**: modify

Add `$(WARNINGS_AS_ERRORS) \` as its own continuation line, immediately before
the final action word. Keep the `CODE_SIGNING_ALLOWED=NO` line.

```makefile
build-mac:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination 'platform=macOS' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  CODE_SIGNING_ALLOWED=NO \
	  $(WARNINGS_AS_ERRORS) \
	  build
```

**Do not touch `build-mac-signed`** — it must keep exactly its current recipe.

#### 3. Discard the unused `refresh()` result

**File**: `CheckStitch/ContentView.swift`
**Action**: modify (line 100)

```swift
                .refreshable { _ = await syncService.refresh() }
```

`ChecklistSyncService.refresh()` keeps its `async -> SyncOutcome` contract; the
Void-returning `.refreshable` closure now discards explicitly.

#### 4. Disambiguate the trailing closure

**File**: `CheckStitch/ChecklistStore.swift`
**Action**: modify (line 226, inside `rename(id:to:)`)

```swift
        guard checklists.first(where: { $0.id != id && Self.sameName($0.name, name) }) == nil else {
```

Parenthesizing the `where:` argument is exactly what the diagnostic asks for
("pass as a parenthesized argument"); `Sequence.first(where:)` has identical
semantics to the trailing-closure form, so behaviour is unchanged.

#### 5. Harness regression case (build-mac only, for now)

**File**: `scripts/tests/run.sh`
**Action**: modify

Add a new section before the final `echo "tests: ..."` summary. The legs array
is the single place later phases append to; the helper and the sad-path case
never change.

```bash
# --- warnings-as-errors enforcement ----------------------------------------

# Every gate leg that compiles Swift must carry the shared Makefile
# warnings-as-errors setting. Later phases append their leg here.
WARNINGS_AS_ERRORS_LEGS=(build-mac)

# True when every xcodebuild argv line in $1 carries both compiler flags.
warnings_as_errors_logged() {
    [[ -s "$1" ]] || return 1
    awk '
        { n++ }
        /SWIFT_TREAT_WARNINGS_AS_ERRORS=YES/ && /GCC_TREAT_WARNINGS_AS_ERRORS=YES/ { ok++ }
        END { exit (n > 0 && ok == n) ? 0 : 1 }
    ' "$1"
}

# Drive the real Makefile with a stubbed xcodebuild (no compiler, no simulator)
# and assert the flag reaches every enforced leg.
warnings_as_errors_reaches_compiling_legs() {
    new_stubs xcodebuild
    export SIM="platform=iOS Simulator,id=WARNINGS-AS-ERRORS-UDID"
    local leg
    for leg in "${WARNINGS_AS_ERRORS_LEGS[@]}"; do
        : >"$STUB_ROOT/xcodebuild.log"
        make "$leg" >/dev/null 2>&1 || return 1
        warnings_as_errors_logged "$STUB_ROOT/xcodebuild.log" || return 1
    done
}

# Sad path: the guard must fail when the setting is stripped from a recipe.
warnings_as_errors_guard_detects_a_stripped_flag() {
    new_stubs xcodebuild
    export SIM="platform=iOS Simulator,id=WARNINGS-AS-ERRORS-UDID"
    local mf="$STUB_ROOT/Makefile"
    sed 's/ \$(WARNINGS_AS_ERRORS)//' Makefile >"$mf"
    : >"$STUB_ROOT/xcodebuild.log"
    make -f "$mf" build-mac >/dev/null 2>&1 || return 1
    ! warnings_as_errors_logged "$STUB_ROOT/xcodebuild.log"
}

run_case warnings_as_errors_reaches_compiling_legs warnings_as_errors_reaches_compiling_legs
run_case warnings_as_errors_guard_detects_a_stripped_flag warnings_as_errors_guard_detects_a_stripped_flag
```

Notes:
- Do **not** stub `make` for these cases — the real Makefile is the thing under
  test. `new_stubs xcodebuild` reaps any previous stub tree, so the real `make`
  is on `PATH` again.
- `SIM` is exported so the `build`/`test-ui` legs (later phases) get a literal
  destination instead of the shared `name=iPhone 17` default.
- The `sed` copies the Makefile to `$STUB_ROOT`; `make -f` still runs recipes in
  the repo root, so relative paths resolve.

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` → ends with `tests: N passed, 0 failed`; both new cases `ok`
- [x] `make build-mac` exits 0 and prints no `warning:` lines (the AppIntents metadata note is not a compiler warning)
- [x] `grep -n 'WARNINGS_AS_ERRORS' Makefile` shows the declaration and exactly one `build-mac` recipe line; `build-mac-signed` is unchanged (`git diff Makefile`)

#### Manual
- [ ] Inject a warning and confirm the leg fails, then revert:
  `printf '\nfunc __warnProbe() {\n    let unusedProbe = 1\n}\n' >> CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift`
  → `make build-mac` exits non-zero with `error: initialization of immutable value 'unusedProbe' was never used`
  → `git checkout -- CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift`

---

## Phase 2: iOS simulator build leg enforced

`make build` fails on any warning. No new source fixes are expected — the iOS
leg emits exactly the two Phase 1 sites (verified).

### Changes

#### 1. `build` recipe

**File**: `Makefile`
**Action**: modify

```makefile
build:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  $(WARNINGS_AS_ERRORS) \
	  build
```

#### 2. Harness leg list

**File**: `scripts/tests/run.sh`
**Action**: modify

```bash
WARNINGS_AS_ERRORS_LEGS=(build-mac build)
```

If a real `make build` with the flags on reveals an iOS-only site beyond the
two Phase 1 fixes, fix it at source in `CheckStitch/*.swift` with the same
minimal semantic-preserving edit and record the `file:line` in the completion
artifact. (The fresh-DerivedData inventory found none.)

### Verification

#### Automated
- [x] `make build` exits 0 and prints no compiler `warning:` lines
- [x] `bash scripts/tests/run.sh` → `0 failed`, `warnings_as_errors_reaches_compiling_legs` ok

#### Manual
- [ ] Re-run the deliberate-warning probe above; confirm both `make build` and `make build-mac` now fail on it, then revert

---

## Phase 3: Unit-test leg enforced

`make test-unit` fails on any warning, and all 9 test-target warnings are fixed.

### Changes

#### 1. `test-unit` recipe

**File**: `Makefile`
**Action**: modify

```makefile
test-unit:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(MAC_SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  CODE_SIGNING_ALLOWED=NO \
	  $(WARNINGS_AS_ERRORS) \
	  -only-testing:CheckStitchTests \
	  test
```

#### 2. Redundant `#require` on a non-optional (4 sites)

**File**: `CheckStitchTests/WatchChecklistStoreTests.swift`
**Action**: modify (lines 59, 142, 158, 183)

Replace the identical line at each of the four sites:

```swift
        let runID = store.run(checklist)          // was: try #require(store.run(checklist))
```

`WatchChecklistStore.run()` returns a non-optional `UUID`
(`CheckStitchCore/Sources/CheckStitchCore/ChecklistSync.swift:281-282`), so the
macro was a no-op. The genuine `#require` at line 230
(`store.checklists.first?.items.first`) stays untouched, as does every other
`#require` in the repo. `run()`'s API is unchanged.

#### 3. Unused immutable bindings (5 sites)

**File**: `CheckStitchTests/ChecklistImportSessionTests.swift`
**Action**: modify (lines 82, 88)

`prepare(data:)` returns `[ChecklistImportCandidate]` and is **not**
`@discardableResult`, so the discard must be explicit:

```swift
        _ = try session.prepare(data: payload([Checklist(name: "V1")], version: 1))
        ...
        _ = try session.prepare(data: payload([Checklist(name: "V2")], version: 2))
```

The `let v1`/`let v2` names were documentary only (the nearby `#expect` message
strings say "v1 payload…"/"v2 payload…").

**File**: `CheckStitchTests/ChecklistStoreTests.swift`
**Action**: modify (lines 1295, 1296, 1456)

`ChecklistStore.create(name:)` **is** `@discardableResult`
(`CheckStitch/ChecklistStore.swift:133-134`), so `_ =` is explicit and
warning-free:

```swift
        // testMoveChecklistsPreservesChecklistIdentity
        _ = store.create(name: "Hardware")
        _ = store.create(name: "Travel")
```

```swift
        // testApplyMergesRemoteChecklist
        _ = store.create()
```

Careful: `let created = store.create()` appears ~33 times in this file and
`let created = store.create()` followed by a `ChecklistEnvelope` also occurs at
line 1476 — where `created.id` **is** used. Only line 1456 is in scope; match it
by its unique 5-line context (`checklists: [Checklist(id: UUID(), name:
"Remote",`). Leave line 1476 and all other `created` bindings alone.

#### 4. Harness leg list

**File**: `scripts/tests/run.sh`
**Action**: modify

```bash
WARNINGS_AS_ERRORS_LEGS=(build-mac build test-unit)
```

### Verification

#### Automated
- [ ] `make test-unit` exits 0, prints `** TEST SUCCEEDED **`, and no compiler `warning:` lines
- [ ] `bash scripts/tests/run.sh` → `0 failed`

#### Manual
- [ ] Confirm the four `#require` sites and line 230: `grep -n 'try #require' CheckStitchTests/WatchChecklistStoreTests.swift` shows only line 230
- [ ] Confirm line 1476's `created` is still referenced: `sed -n '1470,1482p' CheckStitchTests/ChecklistStoreTests.swift`

---

## Phase 4: UI-test and watch legs enforced

`make test-ui` and `make watch-build` fail on any warning. No new source fixes
are expected: `CheckStitchUITests.swift` is clean, and the unit-test target
that `build-for-testing` also compiles was fixed in Phase 3.

### Changes

#### 1. `test-ui` recipe (both invocations)

**File**: `Makefile`
**Action**: modify

```makefile
test-ui:
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  $(WARNINGS_AS_ERRORS) \
	  build-for-testing
	xcodebuild -scheme '$(SCHEME)' \
	  -destination '$(SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  $(WARNINGS_AS_ERRORS) \
	  -only-testing:CheckStitchUITests \
	  test-without-building
```

`test-without-building` compiles nothing, so the flag there is inert; it is
included for uniformity and because the harness asserts every `xcodebuild`
argv line.

#### 2. `watch-build` recipe

**File**: `Makefile`
**Action**: modify

```makefile
watch-build:
	xcodebuild -scheme '$(WATCH_SCHEME)' \
	  -destination '$(WATCH_SIM)' \
	  -configuration '$(CONFIGURATION)' \
	  -derivedDataPath '$(DERIVED_DATA)' \
	  $(WARNINGS_AS_ERRORS) \
	  build
```

#### 3. Harness leg list (complete)

**File**: `scripts/tests/run.sh`
**Action**: modify

```bash
WARNINGS_AS_ERRORS_LEGS=(build-mac build test-unit test-ui watch-build)
```

### Verification

#### Automated
- [ ] `make watch-build` exits 0 with no compiler `warning:` lines
- [ ] `make test-ui` exits 0 (boots this worktree's `.simulator_id` simulator; run under the gate's lock or accept a window)
- [ ] `bash scripts/tests/run.sh` → `0 failed`; `warnings_as_errors_reaches_compiling_legs` logs 2 `xcodebuild` calls for `test-ui`

#### Manual
- [ ] Deliberate-warning probe: confirm `make watch-build` and `make test-ui` fail on it, then revert

---

## Phase 5: Hardening — full-gate confidence and docs

The whole gate is green with enforcement on every leg, CI inherits it, and the
guard is documented so it survives recipe refactors.

### Changes

#### 1. Document the contract

**File**: `Makefile`
**Action**: modify (comment on `WARNINGS_AS_ERRORS`)

Append to the Phase 1 comment block so the pointer to the guard is explicit:

```makefile
# Gate legs compile with warnings as errors: a compiler warning fails the leg.
# scripts/test.sh and CI inherit this through the make recipes; local Xcode
# builds and project.pbxproj are untouched. `build-mac-signed`,
# run-watch.sh and run-devices.sh are device helpers and deliberately excluded.
# scripts/tests/run.sh pins every enforced leg (WARNINGS_AS_ERRORS_LEGS).
WARNINGS_AS_ERRORS := SWIFT_TREAT_WARNINGS_AS_ERRORS=YES GCC_TREAT_WARNINGS_AS_ERRORS=YES
```

#### 2. Document the gate behaviour

**File**: `AGENTS.md`
**Action**: modify (append to the "Build, run, gate" section)

```markdown
- Every gate leg that compiles Swift passes the shared `WARNINGS_AS_ERRORS`
  Makefile variable (`SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
  GCC_TREAT_WARNINGS_AS_ERRORS=YES`), so a compiler warning fails the gate.
  `scripts/tests/run.sh` (`warnings_as_errors_reaches_compiling_legs`) pins the
  flag per leg; `build-mac-signed`, `run-watch.sh` and `run-devices.sh` are
  intentionally outside enforcement.
```

#### 3. CI

**File**: `.github/workflows/dependabot-checks.yml`
**Action**: none — no edit.

CI invokes `make build`, `make test-unit`, `make build-mac`, `make watch-build`
and `bash scripts/tests/run.sh` as separate steps, so it inherits enforcement
through the recipes by construction. (CI does not run `make test-ui`; the local
gate does.)

### Verification

#### Automated
- [ ] `./scripts/test.sh` prints `gate: ok` (its three own `warning:` lines, if any, are unchanged and unrelated)
- [ ] `bash scripts/tests/run.sh` → `0 failed`
- [ ] `shellcheck scripts/*.sh scripts/tests/*.sh` clean
- [ ] Fresh-cache confidence run: `rm -rf DerivedData && ./scripts/test.sh` → `gate: ok` (authoritative, since incremental DerivedData can skip recompiles)

#### Manual
- [ ] For each of `make build-mac`, `make build`, `make test-unit`, `make watch-build`, inject the `__warnProbe` warning, confirm that leg fails, then revert — one representative leg is enough if time-boxed, but CI on a fresh checkout is the backstop
- [ ] Confirm the AppIntents metadata note does **not** fail any leg (it is a build-phase message, not a diagnostic)

---

## Deviations from structure.md

1. **Phase 1 file list** now names `CheckStitch/ChecklistStore.swift`
   explicitly. The real trailing-closure site is `:226`; the structure's
   shape-inferred candidates (`:353`/`:371`/`:259`) do not fire, and there is
   only **one** such warning (the design table said two).
2. **Phase 3 adds `ChecklistStoreTests.swift:1456`** (unused `created`), a site
   `research.md` explicitly said did not exist. Same file, so the file list is
   unchanged; only the site list grows.
3. **Phase 4 gains a dependency note**: `make test-ui`'s `build-for-testing`
   also compiles `CheckStitchTests` for the simulator, so it surfaces the same
   9 test-target warnings. Phase ordering (Phase 3 before Phase 4) already makes
   this correct; no reordering needed. `CheckStitchUITests.swift` is confirmed
   clean.
4. **No source fix in Phase 2 or Phase 4** — verified by a fresh-DerivedData
   warning inventory rather than assumed.
5. **The SPM-propagation open risk is resolved**: the command-line override
   does reach `CheckStitchCore` package targets (validated with a reverted
   probe), so Core is enforced too.

## Known limitations

- **Incremental `DerivedData` can hide warnings.** Legs share `DerivedData`, so
  a cached compile skips unchanged files and warnings-as-errors only fires for
  files actually recompiled; a local gate can therefore pass spuriously. CI on a
  fresh checkout is the authoritative backstop, and the Phase 5 verification
  includes one `rm -rf DerivedData && ./scripts/test.sh` confidence run. A clean
  build is deliberately not added to the gate (runtime cost).
- **Harness argv assertion durability.** If the Makefile recipes are refactored
  (e.g. flags move to an xcconfig), `WARNINGS_AS_ERRORS_LEGS` /
  `warnings_as_errors_logged` must move with them; the sad-path case fails loudly
  if the flag silently disappears.
- **Manual probes mutate source.** Every deliberate-warning check must end with
  `git checkout -- <file>`; the probe in the plan uses a throwaway function so
  the revert is unambiguous.
