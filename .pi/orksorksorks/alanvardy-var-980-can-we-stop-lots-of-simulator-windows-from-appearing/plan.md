# Implementation Plan

## Overview

Running the gate (`bash scripts/test.sh`) must produce **no** Simulator window even
while `Simulator.app` is open and other agents run gates concurrently; `make run`
still opens exactly one window on this worktree's own `.simulator_id` device. The
design asserts a per-host `com.apple.iphonesimulator AutoOpenDevice=false`
preference, pre-boots this worktree's UDID headlessly in the gate with a scoped
trap-shutdown, and makes `make run` request the window explicitly, UDID-pinned.

All layers are shell. Since the repo has no shell test harness, this plan adds a
tiny plain-bash assertion runner (`scripts/tests/run.sh`) that the gate invokes
before printing `gate: ok`.

**Test seam used throughout**: the runner puts stubbed `xcrun`, `defaults`,
`make`, and `open` executables on `PATH` so the gate and helpers can be exercised
without touching a real simulator. The gate reads its worktree id file through
`SIM_ID_FILE` (default `.simulator_id`) and skips the runner when
`GATE_TESTS_SKIP=1`, which is how gate-level tests invoke the gate without
recursion.

---

## Phase 1: Host windowless-preference helper + spike

### Changes

#### 1. `scripts/sim-windowless.sh` (new)
**File**: `scripts/sim-windowless.sh`
**Action**: create (`chmod 100755` before commit)

`check` exits 0 when the pref is exactly `0`; otherwise it prints the exact `fix`
command to stderr and exits 1. `fix` writes the pref and is **never** called by
the gate. The body is guarded by a BASH_SOURCE check so tests can `source` the
script and call `windowless_pref_ok` directly.

```bash
#!/bin/bash
# Assert/fix the per-host Simulator.app preference that stops it auto-opening a
# window for every booted device. See 'Simulator windows' in AGENTS.md.
set -euo pipefail

DOMAIN="com.apple.iphonesimulator"
KEY="AutoOpenDevice"

# True when Simulator.app will *not* auto-attach a window to booted devices.
windowless_pref_ok() {
    local value
    value="$(defaults read "$DOMAIN" "$KEY" 2>/dev/null || true)"
    [[ "$value" == "0" ]]
}

main() {
    case "${1:-}" in
    check)
        if windowless_pref_ok; then
            return 0
        fi
        echo "warning: Simulator.app auto-open is on (${DOMAIN} ${KEY} is not 0)." >&2
        echo "         Simulator windows will appear while 'make test' runs." >&2
        echo "         One-time host fix: bash scripts/sim-windowless.sh fix" >&2
        return 1
        ;;
    fix)
        defaults write "$DOMAIN" "$KEY" -bool false
        echo "Wrote ${DOMAIN} ${KEY} = false"
        ;;
    *)
        echo "usage: sim-windowless.sh {check|fix}" >&2
        return 2
        ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
```

#### 2. `scripts/tests/run.sh` (new)
**File**: `scripts/tests/run.sh`
**Action**: create (`chmod 100755` before commit)

Plain-bash assertion runner. Owns the stub machinery used by every later phase.
Phase 1 fills in the first two cases; later phases append their own.

```bash
#!/bin/bash
# Shell-level regression tests for the gate and simulator helpers.
# Run directly, or from the gate (which sets GATE_TESTS_SKIP=1 for children).
set -euo pipefail

cd "$(dirname "$0")/../.."

PASS=0
FAIL=0
STUB_ROOT=""

cleanup() {
    [[ -n "$STUB_ROOT" && -d "$STUB_ROOT" ]] && rm -rf "$STUB_ROOT"
}
trap cleanup EXIT

# Create a temp dir of stub executables and prepend it to PATH.
# Each stub appends its argv to "$STUB_ROOT/<name>.log".
new_stubs() {
    STUB_ROOT="$(mktemp -d)"
    local name
    for name in "$@"; do
        cat >"$STUB_ROOT/$name" <<STUB
#!/bin/bash
echo "\$*" >>"$STUB_ROOT/$name.log"
exit 0
STUB
        chmod +x "$STUB_ROOT/$name"
    done
    PATH="$STUB_ROOT:$PATH"
    export PATH
}

run_case() {
    local name="$1"
    shift
    if "$@"; then
        PASS=$((PASS + 1))
        echo "ok: $name"
    else
        FAIL=$((FAIL + 1))
        echo "FAIL: $name" >&2
    fi
}

# --- Phase 1 ---------------------------------------------------------------

check_reports_ok_when_pref_false() {
    new_stubs defaults
    cat >"$STUB_ROOT/defaults" <<STUB
#!/bin/bash
echo 0
STUB
    chmod +x "$STUB_ROOT/defaults"
    bash scripts/sim-windowless.sh check
}

check_reports_fix_when_pref_missing_or_true() {
    local out status
    for value in "" 1; do
        new_stubs defaults
        printf '#!/bin/bash\necho "%s"\n' "$value" >"$STUB_ROOT/defaults"
        chmod +x "$STUB_ROOT/defaults"
        set +e
        out="$(bash scripts/sim-windowless.sh check 2>&1)"
        status=$?
        set -e
        [[ $status -ne 0 ]] || return 1
        [[ "$out" == *"sim-windowless.sh fix"* ]] || return 1
    done
}

run_case check_reports_ok_when_pref_false check_reports_ok_when_pref_false
run_case check_reports_fix_when_pref_missing_or_true check_reports_fix_when_pref_missing_or_true

echo "tests: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
```

> Note: stubs write to `${STUB_ROOT}/<name>.log`; later phases set `STUB_ROOT`
> **without** re-creating it when they need to read a log. `new_stubs` always
> makes a fresh dir, so read logs immediately after the call.

#### 3. `scripts/test.sh`
**File**: `scripts/test.sh`
**Action**: modify

Run the shell runner before `gate: ok`, and extend lint to cover it.

```bash
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
```

#### 4. `AGENTS.md`
**File**: `AGENTS.md`
**Action**: modify (Phase 5 completes the prose; Phase 1 adds the minimal note)

Add to the "Build, run, gate" section:

```markdown
- One-time host setup: `bash scripts/sim-windowless.sh fix` asserts
  `com.apple.iphonesimulator AutoOpenDevice=false` so a running `Simulator.app`
  does not attach a window to every booted device. The gate checks this and warns
  (it does not write host preferences). Shell-level regression tests live in
  `scripts/tests/run.sh` and run as part of the gate.
```

### Verification

#### Automated
- [x] `chmod +x scripts/sim-windowless.sh scripts/tests/run.sh` then `git diff --summary` shows mode `100755` for both
- [x] `bash -n scripts/sim-windowless.sh && bash -n scripts/tests/run.sh` exits 0
- [x] `bash scripts/tests/run.sh` prints `ok: check_reports_ok_when_pref_false`, `ok: check_reports_fix_when_pref_missing_or_true`, `tests: 2 passed, 0 failed`
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` exits 0 (or `bash -n` fallback)
- [x] `bash scripts/test.sh` prints `gate: ok` (run by the parent after Phase 5)

#### Manual — the spike (must pass before Phase 3; record the result in this file)
- [ ] Confirm the pref is currently absent: `defaults read com.apple.iphonesimulator AutoOpenDevice` → `does not exist` (observed on this host at plan time)
- [ ] Open `Simulator.app` and leave it running (pid visible via `pgrep -x Simulator`)
- [ ] `bash scripts/sim-windowless.sh check` exits 1 and prints the fix command
- [ ] `bash scripts/sim-windowless.sh fix`; `defaults read com.apple.iphonesimulator AutoOpenDevice` → `0`
- [ ] With `Simulator.app` still running, boot **this worktree's** UDID (read it from `.simulator_id`; currently `D82898D5-C8E0-4C92-8989-EE599C30FEA4`): `xcrun simctl boot <UDID>` (ignore "already booted"), then `xcrun simctl bootstatus <UDID> -b`
- [ ] **Observe: no Simulator window appears.** Count windows before/after:
      `osascript -e 'tell application "System Events" to tell process "Simulator" to count windows'`
- [ ] Run the real UI test path windowless: `make test-ui`; window count stays flat
- [ ] Spike outcome recorded — if the pref has **no** effect, **stop and take Phase 4b**; do not proceed to Phase 3 on an unproven guarantee
- [ ] Clean up: `xcrun simctl shutdown <UDID>`

> **Spike outcome (recorded by the implement step, 2026-09-12, Xcode 26.6 /
> iOS 27.0): pref INEFFECTIVE — Phase 4b selected.** All preconditions
> confirmed (pref absent; Simulator.app running; `check` exits 1 and prints the
> fix command; `fix` writes `0`). But with `AutoOpenDevice` = 0 and
> Simulator.app running, booting the worktree UDID **still opened a window**
> (count 1→2; title `sim-alanvardy-var-980-can-we-stop-lots-of-simulator-windows-from-appearing – iOS 27.0`).
> Repeating after quitting and relaunching Simulator.app with the pref already
> set had the same result (1→2), so the pref is also not launch-time-only — it
> is simply ineffective on this toolchain. Per the trigger above, Phase 3
> implements the **host-scoped lock (Phase 4b)** instead of the
> `sim-windowless.sh check` line; `scripts/sim-windowless.sh` and its Phase 1
> runner cases are dropped.

---

## Phase 2: Shared UDID resolver

### Changes

#### 1. `scripts/resolve-sim-udid.sh` (new)
**File**: `scripts/resolve-sim-udid.sh`
**Action**: create (`chmod 100755` before commit)

Extracted verbatim from `scripts/run-simulator.sh:20-28` semantics, plus an
optional `--require-id` that refuses name-form destinations.

```bash
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
        | grep -F "$NAME (" | head -1 | sed -E 's/.*\(([A-F0-9-]+)\).*/\1/')"
fi

if [[ -z "$UDID" ]]; then
    echo "ERROR: could not resolve a simulator for '$SIM'" >&2
    exit 1
fi

printf '%s\n' "$UDID"
```

#### 2. `scripts/run-simulator.sh`
**File**: `scripts/run-simulator.sh`
**Action**: modify — replace the inline resolution block (`:20-37`) with a call

Delete the `if [[ "$SIM" == *",id="* ]] … fi` block and the "could not resolve"
check; keep the app-bundle check.

```bash
# Resolve the destination to a concrete UDID.
if ! UDID="$(bash "$(dirname "$0")/resolve-sim-udid.sh" "$SIM")"; then
    exit 1
fi
if [[ ! -d "$APP" ]]; then
    echo "ERROR: app bundle not found at $APP (run 'make build' first)" >&2
    exit 1
fi
```

The resolver prints the existing `ERROR: could not resolve a simulator for '…'`
message, so behaviour and message text are unchanged.

#### 3. `scripts/tests/run.sh`
**File**: `scripts/tests/run.sh`
**Action**: modify — append Phase 2 cases

```bash
# --- Phase 2 ---------------------------------------------------------------

resolves_id_form_directly() {
    new_stubs xcrun
    out="$(bash scripts/resolve-sim-udid.sh 'platform=iOS Simulator,id=ABC-123')"
    [[ "$out" == "ABC-123" ]]
}

resolves_name_form_from_simctl_list() {
    new_stubs xcrun
    cat >"$STUB_ROOT/xcrun" <<'STUB'
#!/bin/bash
echo "    iPhone 17 (ABCD-1234) (Shutdown)"
STUB
    chmod +x "$STUB_ROOT/xcrun"
    out="$(bash scripts/resolve-sim-udid.sh 'platform=iOS Simulator,name=iPhone 17')"
    [[ "$out" == "ABCD-1234" ]]
}

errors_on_unknown_name() {
    new_stubs xcrun
    set +e
    out="$(bash scripts/resolve-sim-udid.sh 'platform=iOS Simulator,name=No Such Device' 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"could not resolve a simulator"* ]]
}

require_id_rejects_name_form() {
    new_stubs xcrun
    set +e
    out="$(bash scripts/resolve-sim-udid.sh --require-id 'platform=iOS Simulator,name=iPhone 17' 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"not pinned"* ]]
}

run_case resolves_id_form_directly resolves_id_form_directly
run_case resolves_name_form_from_simctl_list resolves_name_form_from_simctl_list
run_case errors_on_unknown_name errors_on_unknown_name
run_case require_id_rejects_name_form require_id_rejects_name_form
```

### Verification

#### Automated
- [x] `chmod +x scripts/resolve-sim-udid.sh`; mode is `100755`
- [x] `bash scripts/tests/run.sh` → `tests: 6 passed, 0 failed`
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` exits 0
- [x] `bash scripts/test.sh` prints `gate: ok` (gate behaviour unchanged in this phase; verified by the parent's post-Phase-5 gate run)

#### Manual
- [ ] `bash scripts/run-simulator.sh 'platform=iOS Simulator,id=<UDID from .simulator_id>' DerivedData/Build/Products/Debug-iphonesimulator/CheckStitch.app` still boots/installs/launches (or `make run`)
- [ ] `bash scripts/run-simulator.sh 'platform=iOS Simulator,name=iPhone 17' …` still resolves by name (no regression in the fallback path)

---

## Phase 3: Gate pre-boot + scoped trap-shutdown

### Changes

#### 1. `scripts/test.sh`
**File**: `scripts/test.sh`
**Action**: modify — the gate sequence

Full intended body:

```bash
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

if ! bash scripts/sim-windowless.sh check; then
  echo "warning: continuing — the gate may open Simulator windows on this host" >&2
fi

if [[ -n "$GATE_UDID" ]]; then
  echo "==> Pre-booting gate simulator $GATE_UDID…"
  xcrun simctl boot "$GATE_UDID" 2>/dev/null || true
  xcrun simctl bootstatus "$GATE_UDID" -b
  trap 'xcrun simctl shutdown "$GATE_UDID" 2>/dev/null || true' EXIT
else
  echo "warning: no worktree simulator id — skipping pre-boot and shutdown" >&2
fi

make test

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
```

Notes:
- The trap is installed **only** when a UDID resolved; it always targets
  `"$GATE_UDID"` — `all`/`booted` never appear.
- The `sim-windowless.sh check` warning goes to stderr but the gate continues
  (design Decision 5: assert, don't hard-fail).
- `SIM` env is honoured so an explicit `SIM=…,id=…` gate run pre-boots that
  device; an explicit name-form `SIM=` resolves to nothing and the gate skips.

#### 2. `scripts/tests/run.sh`
**File**: `scripts/tests/run.sh`
**Action**: modify — append Phase 3 cases

Both cases run the real gate with stubbed `make`/`xcrun`/`defaults`/`open` and
`GATE_TESTS_SKIP=1`, so the runner is not re-entered.

```bash
# --- Phase 3 ---------------------------------------------------------------

stub_gate_command() {
    new_stubs make xcrun defaults open
    cat >"$STUB_ROOT/defaults" <<'STUB'
#!/bin/bash
echo 0
STUB
    chmod +x "$STUB_ROOT/defaults"
}

gate_skips_preboot_without_own_udid() {
    stub_gate_command
    SIM_ID_FILE="$STUB_ROOT/absent.simulator_id" GATE_TESTS_SKIP=1 bash scripts/test.sh >/dev/null 2>&1 || return 1
    [[ ! -s "$STUB_ROOT/xcrun.log" ]]
}

gate_shuts_down_only_resolved_udid() {
    stub_gate_command
    printf 'GATE-UDID-1\n' >"$STUB_ROOT/sim_id"
    SIM_ID_FILE="$STUB_ROOT/sim_id" GATE_TESTS_SKIP=1 bash scripts/test.sh >/dev/null 2>&1 || return 1
    grep -q 'boot GATE-UDID-1' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'bootstatus GATE-UDID-1 -b' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'shutdown GATE-UDID-1' "$STUB_ROOT/xcrun.log" || return 1
    # Never a global selector.
    ! grep -Eq 'shutdown (all|booted)|boot (all|booted)' "$STUB_ROOT/xcrun.log"
}

run_case gate_skips_preboot_without_own_udid gate_skips_preboot_without_own_udid
run_case gate_shuts_down_only_resolved_udid gate_shuts_down_only_resolved_udid
```

> The stubbed `xcrun` appends its argv, so a bare `boot`/`shutdown` line would
> still be caught by the global-selector grep. `GATE-UDID-1` is intentionally not
> a real UUID: `--require-id` parses `,id=` textually and never calls `xcrun`.

#### 3. `AGENTS.md`
**File**: `AGENTS.md`
**Action**: modify

Add to "Build, run, gate":

```markdown
- The gate pre-boots this worktree's `.simulator_id` device headlessly before
  `make test` and shuts it down on exit (scoped to that UDID only — never
  `all`/`booted`). If `.simulator_id` is missing it skips pre-boot entirely and
  never selects a shared device.
```

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` → `tests: 7 passed, 0 failed` (Phase 4b substitution)
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` exits 0
- [x] `bash scripts/test.sh` prints `gate: ok` (real gate; parent run after Phase 5)
- [x] `xcrun simctl list devices booted` shows **no** device whose UDID equals `.simulator_id` after the gate exits (pre-boot line present in the run, booted list empty after — scoped trap shutdown fired)

> Implemented with the **Phase 4b substitution** (spike failed): the host-scoped
> lock + quit-Simulator.app block replaces the `sim-windowless.sh check` line;
> `scripts/sim-windowless.sh` and its Phase 1 runner cases were dropped. The
> Phase 3 shutdown trap and the Phase 4b lock release share ONE `gate_cleanup`
> EXIT trap (a second `trap … EXIT` would replace the first).

#### Manual
- [ ] With `Simulator.app` open and the Phase 1 pref applied: run `bash scripts/test.sh`; window count (`osascript` above) stays flat from start to finish
- [ ] In two terminals simultaneously run `bash scripts/test.sh`; both reach `gate: ok` and the window count stays flat (no cross-shutdown)
- [ ] If the Phase 1 spike failed: implement Phase 4b instead of this phase's `sim-windowless.sh check` line and record the substitution

---

## Phase 4: `make run` opens its own window explicitly

### Changes

#### 1. `scripts/run-simulator.sh`
**File**: `scripts/run-simulator.sh`
**Action**: modify — add a window request after boot

```bash
echo "==> Booting simulator $UDID…"
xcrun simctl boot "$UDID" 2>/dev/null || true
xcrun simctl bootstatus "$UDID" -b

echo "==> Opening Simulator window for $UDID…"
open -a Simulator --args -CurrentDeviceUDID "$UDID"

echo "==> Installing $APP…"
```

> **Confirmed live (2026-09-12):** `open -a Simulator --args
> -CurrentDeviceUDID <udid>` opens/raises the window for the given UDID and
> makes it the frontmost window — primary syntax confirmed, no AppleScript
> fallback needed.

**Spike-dependent syntax.** The Phase 1 spike must confirm
`open -a Simulator --args -CurrentDeviceUDID <udid>` selects the given device. If
it does not (the window opens on whatever device is selected), replace the line
with the AppleScript selection confirmed in the spike:

```bash
osascript <<APPLESCRIPT
tell application "Simulator" to activate
tell application "System Events" to tell process "Simulator"
    repeat with w in windows
        if (value of static text 1 of w) contains "$UDID" then
            perform action "AXRaise" of w
        end if
    end repeat
end tell
APPLESCRIPT
```

The window request lives only on this path: `scripts/test.sh` never calls
`run-simulator.sh`, so the gate cannot reach it.

#### 2. `scripts/tests/run.sh`
**File**: `scripts/tests/run.sh`
**Action**: modify — append Phase 4 case

```bash
# --- Phase 4 ---------------------------------------------------------------

run_path_requests_window_for_resolved_udid() {
    new_stubs make xcrun defaults open
    local app="$STUB_ROOT/CheckStitch.app"
    mkdir -p "$app"
    bash scripts/run-simulator.sh 'platform=iOS Simulator,id=RUN-UDID-1' "$app" >/dev/null 2>&1 || return 1
    grep -q 'RUN-UDID-1' "$STUB_ROOT/open.log"
}

gate_never_requests_a_window() {
    stub_gate_command
    printf 'GATE-UDID-2\n' >"$STUB_ROOT/sim_id"
    SIM_ID_FILE="$STUB_ROOT/sim_id" GATE_TESTS_SKIP=1 bash scripts/test.sh >/dev/null 2>&1 || return 1
    [[ ! -s "$STUB_ROOT/open.log" ]]
}

run_case run_path_requests_window_for_resolved_udid run_path_requests_window_for_resolved_udid
run_case gate_never_requests_a_window gate_never_requests_a_window
```

> `run_path_requests_window_for_resolved_udid` shadows `open` via the stub, so
> the real Simulator is never launched by tests.

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` → `tests: 9 passed, 0 failed` (Phase 4b substitution)
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` exits 0
- [x] `bash scripts/test.sh` prints `gate: ok` and no window appears (gate quit Simulator.app; it stayed quit — neither xcodebuild nor the runner relaunched it)

#### Manual
- [ ] `make run` finishes with `✅ Launched app.alanvardy.CheckStitch on <UDID>`, and **exactly one** window is open on the device whose UDID is in `.simulator_id` (verify via `xcrun simctl list devices booted` and the window title)
- [ ] While that window is open, run `bash scripts/test.sh` in another terminal: the gate completes `gate: ok` and the `make run` window is **not** closed

---

## Phase 4b: Fallback host-scoped lock (only if the Phase 1 spike fails)

**Do not implement unless the spike proved `AutoOpenDevice` ineffective.** This
replaces the `sim-windowless.sh check` line in Phase 3; Phases 2, 4, 5 and the
trap-shutdown stay as written, and `scripts/sim-windowless.sh` is dropped (delete
it and its Phase 1 test cases).

### Changes

#### 1. `scripts/test.sh`
**File**: `scripts/test.sh`
**Action**: modify — wrap the test body in a bounded host lock

```bash
LOCK_DIR="${TMPDIR:-/tmp}/checkstitch-simulator.lock"
LOCK_TIMEOUT="${LOCK_TIMEOUT:-60}"

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

acquire_lock
trap 'release_lock' EXIT
osascript -e 'tell application "Simulator" to quit' 2>/dev/null || true
```

`acquire_lock` must **degrade to a warning**, never block past `LOCK_TIMEOUT`.
`LOCK_HELD` is initialised to `0` before `acquire_lock`.

#### 2. `scripts/tests/run.sh`
**File**: `scripts/tests/run.sh`
**Action**: modify — replace the Phase 1 cases

```bash
# --- Phase 4b --------------------------------------------------------------

lock_times_out_instead_of_blocking() {
    stub_gate_command
    printf 'GATE-UDID-3\n' >"$STUB_ROOT/sim_id"
    mkdir -p "${TMPDIR:-/tmp}/checkstitch-simulator.lock"
    set +e
    SIM_ID_FILE="$STUB_ROOT/sim_id" LOCK_TIMEOUT=1 GATE_TESTS_SKIP=1 \
        bash scripts/test.sh >/dev/null 2>&1
    status=$?
    set -e
    rmdir "${TMPDIR:-/tmp}/checkstitch-simulator.lock" 2>/dev/null || true
    [[ $status -eq 0 ]]
}

run_case lock_times_out_instead_of_blocking lock_times_out_instead_of_blocking
```

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` → all cases pass, including `lock_times_out_instead_of_blocking`
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` exits 0
- [x] `bash scripts/test.sh` prints `gate: ok` (parent run after Phase 5)

#### Manual
- [ ] Hold the lock (run the gate in one terminal while it sleeps) and start a second gate: the second emits the timeout warning and finishes within `LOCK_TIMEOUT`, windows stay flat
- [ ] After both gates exit, `xcrun simctl list devices booted` has no leftover worktree device

---

## Phase 5: Documentation

### Changes

#### 1. `AGENTS.md`
**File**: `AGENTS.md`
**Action**: modify — final "Simulator windows" subsection

Consolidate the Phase 1/3 notes and record behaviour actually observed. Append
after the "Build, run, gate" bullets:

```markdown
## Simulator windows

- **Why windows appear**: a running `Simulator.app` attaches a window to every
  device booted while it is alive, from any worktree. No `simctl`/`xcodebuild`
  headless flag exists on this toolchain; the GUI is the only lever.
- **One-time host setup**: `bash scripts/sim-windowless.sh fix` writes
  `com.apple.iphonesimulator AutoOpenDevice=false`. The gate runs `check` and
  warns (with the fix command) but never writes host preferences.
- **The gate** pre-boots this worktree's `.simulator_id` UDID headlessly between
  `make build` and `make test`, and trap-shuts-down that UDID on exit. Missing
  `.simulator_id` → skip; never `all`/`booted`.
- **`make run`** requests its window explicitly, pinned to the resolved UDID.
- **Shell tests**: `bash scripts/tests/run.sh`, also run by the gate; stubs
  `xcrun`/`defaults`/`make`/`open` on `PATH`.
- **Spike result (Phase 1)**: [record: pref suppressed the window / pref
  ineffective → Phase 4b host lock in use].
```

Also update the "Build, run, gate" line that says the gate is
`make build → make test → shellcheck` to include the pre-boot and
`scripts/tests/run.sh`.

#### 2. `linear-project.md`
**File**: `linear-project.md`
**Action**: none (no change required).

### Verification

#### Automated
- [x] `bash scripts/tests/run.sh` → all cases pass (9 passed, 0 failed)
- [x] `bash scripts/test.sh` prints `gate: ok` (parent run after Phase 5)
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` exits 0

#### Manual
- [ ] Read `AGENTS.md`; every statement matches observed behaviour from Phases 1–4
- [ ] The recorded spike result is filled in (not a placeholder)
- [x] `git ls-files --stage scripts` shows `100755` for `scripts/resolve-sim-udid.sh` and `scripts/tests/run.sh`; `scripts/sim-windowless.sh` deleted in Phase 3 (Phase 4b)

---

## Testing checkpoints

- After **Phase 1**: `bash scripts/tests/run.sh` green **and** the live spike proves the pref suppresses the window — otherwise stop and take Phase 4b.
- After **Phase 2**: resolver cases green; gate behaviour unchanged (`gate: ok`).
- After **Phase 3**: `gate: ok`, no window appears, no leftover booted device, concurrent gates unaffected.
- After **Phase 4**: `make run` yields exactly one window on the worktree UDID; the gate stays windowless.
- Never advance while the current phase's runner cases or the gate are red.