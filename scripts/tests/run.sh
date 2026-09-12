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

# --- Phase 3 ---------------------------------------------------------------

stub_gate_command() {
    new_stubs make xcrun defaults open osascript
    cat >"$STUB_ROOT/defaults" <<'STUB'
#!/bin/bash
echo 0
STUB
    chmod +x "$STUB_ROOT/defaults"
}

gate_skips_preboot_without_own_udid() {
    stub_gate_command
    SIM_ID_FILE="$STUB_ROOT/absent.simulator_id" GATE_TESTS_SKIP=1 LOCK_TIMEOUT=2 bash scripts/test.sh >/dev/null 2>&1 || return 1
    [[ ! -s "$STUB_ROOT/xcrun.log" ]]
}

gate_shuts_down_only_resolved_udid() {
    stub_gate_command
    printf 'GATE-UDID-1\n' >"$STUB_ROOT/sim_id"
    SIM_ID_FILE="$STUB_ROOT/sim_id" GATE_TESTS_SKIP=1 LOCK_TIMEOUT=2 bash scripts/test.sh >/dev/null 2>&1 || return 1
    grep -q 'boot GATE-UDID-1' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'bootstatus GATE-UDID-1 -b' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'shutdown GATE-UDID-1' "$STUB_ROOT/xcrun.log" || return 1
    # Never a global selector.
    ! grep -Eq 'shutdown (all|booted)|boot (all|booted)' "$STUB_ROOT/xcrun.log"
}

run_case gate_skips_preboot_without_own_udid gate_skips_preboot_without_own_udid
run_case gate_shuts_down_only_resolved_udid gate_shuts_down_only_resolved_udid

# --- Phase 4b (Phase 1 spike proved AutoOpenDevice ineffective; replaces the
# sim-windowless.sh cases that shipped in the Phase 1 commit) -----------------

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
    SIM_ID_FILE="$STUB_ROOT/sim_id" GATE_TESTS_SKIP=1 LOCK_TIMEOUT=2 bash scripts/test.sh >/dev/null 2>&1 || return 1
    [[ ! -s "$STUB_ROOT/open.log" ]]
}

run_case run_path_requests_window_for_resolved_udid run_path_requests_window_for_resolved_udid
run_case gate_never_requests_a_window gate_never_requests_a_window

echo "tests: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]