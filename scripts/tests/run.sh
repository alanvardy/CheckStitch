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
    # Reap the previous stub tree so long runs do not accumulate temp dirs.
    [[ -n "$STUB_ROOT" && -d "$STUB_ROOT" ]] && rm -rf "$STUB_ROOT"
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

require_id_rejects_non_uuid() {
    new_stubs xcrun
    set +e
    out="$(bash scripts/resolve-sim-udid.sh --require-id 'platform=iOS Simulator,id=not-a-udid' 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"not a valid simulator UDID"* ]]
}

run_case resolves_id_form_directly resolves_id_form_directly
run_case resolves_name_form_from_simctl_list resolves_name_form_from_simctl_list
run_case errors_on_unknown_name errors_on_unknown_name
run_case require_id_rejects_name_form require_id_rejects_name_form
run_case require_id_rejects_non_uuid require_id_rejects_non_uuid

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
    env -u SIM SIM_ID_FILE="$STUB_ROOT/absent.simulator_id" GATE_TESTS_SKIP=1 LOCK_TIMEOUT=2 bash scripts/test.sh >/dev/null 2>&1 || return 1
    [[ ! -s "$STUB_ROOT/xcrun.log" ]]
}

gate_shuts_down_only_resolved_udid() {
    stub_gate_command
    printf '11111111-1111-1111-1111-111111111111\n' >"$STUB_ROOT/sim_id"
    env -u SIM SIM_ID_FILE="$STUB_ROOT/sim_id" GATE_TESTS_SKIP=1 LOCK_TIMEOUT=2 bash scripts/test.sh >/dev/null 2>&1 || return 1
    grep -q 'boot 11111111-1111-1111-1111-111111111111' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'bootstatus 11111111-1111-1111-1111-111111111111 -b' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'shutdown 11111111-1111-1111-1111-111111111111' "$STUB_ROOT/xcrun.log" || return 1
    # The window-suppression lever itself must have fired.
    grep -q 'tell application "Simulator" to quit' "$STUB_ROOT/osascript.log" || return 1
    # Never a global selector.
    ! grep -Eq 'shutdown (all|booted)|boot (all|booted)' "$STUB_ROOT/xcrun.log"
}

run_case gate_skips_preboot_without_own_udid gate_skips_preboot_without_own_udid
run_case gate_shuts_down_only_resolved_udid gate_shuts_down_only_resolved_udid

# --- Phase 4b (Phase 1 spike proved AutoOpenDevice ineffective; replaces the
# sim-windowless.sh cases that shipped in the Phase 1 commit) -----------------

lock_times_out_instead_of_blocking() {
    stub_gate_command
    printf '33333333-3333-3333-3333-333333333333\n' >"$STUB_ROOT/sim_id"
    # Private TMPDIR: never poke the live host lock a concurrent gate may hold.
    local lock_tmp="$STUB_ROOT/gate-tmp"
    mkdir -p "$lock_tmp/checkstitch-simulator.lock"
    local out status
    set +e
    out="$(env -u SIM SIM_ID_FILE="$STUB_ROOT/sim_id" LOCK_TIMEOUT=1 GATE_TESTS_SKIP=1 TMPDIR="$lock_tmp" \
        bash scripts/test.sh 2>&1)"
    status=$?
    set -e
    [[ $status -eq 0 ]] || return 1
    [[ "$out" == *"simulator lock busy after 1s"* ]]
}

gate_errors_on_invalid_simulator_id() {
    stub_gate_command
    printf 'not-a-udid\n' >"$STUB_ROOT/sim_id"
    local out status
    set +e
    out="$(env -u SIM SIM_ID_FILE="$STUB_ROOT/sim_id" GATE_TESTS_SKIP=1 LOCK_TIMEOUT=2 bash scripts/test.sh 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"does not name a valid simulator UDID"* ]]
}

stale_lock_is_reaped() {
    stub_gate_command
    printf '44444444-4444-4444-4444-444444444444\n' >"$STUB_ROOT/sim_id"
    local lock_tmp="$STUB_ROOT/gate-tmp"
    mkdir -p "$lock_tmp/checkstitch-simulator.lock"
    # A dead holder PID marks the lock stale, so the gate must not wait it out.
    printf '999999\n' >"$lock_tmp/checkstitch-simulator.lock/pid"
    local out
    out="$(env -u SIM SIM_ID_FILE="$STUB_ROOT/sim_id" LOCK_TIMEOUT=1 GATE_TESTS_SKIP=1 TMPDIR="$lock_tmp" \
        bash scripts/test.sh 2>&1)" || return 1
    [[ "$out" != *"simulator lock busy"* ]] || return 1
    [[ "$out" == *"Pre-booting gate simulator 44444444-4444-4444-4444-444444444444"* ]]
}

run_case lock_times_out_instead_of_blocking lock_times_out_instead_of_blocking
run_case gate_errors_on_invalid_simulator_id gate_errors_on_invalid_simulator_id
run_case stale_lock_is_reaped stale_lock_is_reaped

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
    printf '22222222-2222-2222-2222-222222222222\n' >"$STUB_ROOT/sim_id"
    env -u SIM SIM_ID_FILE="$STUB_ROOT/sim_id" GATE_TESTS_SKIP=1 LOCK_TIMEOUT=2 bash scripts/test.sh >/dev/null 2>&1 || return 1
    [[ ! -s "$STUB_ROOT/open.log" ]]
}

run_case run_path_requests_window_for_resolved_udid run_path_requests_window_for_resolved_udid
run_case gate_never_requests_a_window gate_never_requests_a_window

# --- run-watch.sh ----------------------------------------------------------

WATCH_FIXTURE=""

# Stub xcrun so `devicectl list devices -j <file>` writes a fixture, while any
# install/launch subcommand is only logged. xcodebuild is a no-op (the built
# app is pre-created by the caller).
stub_watch_command() {
    new_stubs xcrun xcodebuild
    WATCH_FIXTURE="$STUB_ROOT/devices.json"
    cat >"$WATCH_FIXTURE" <<'JSON'
{"result":{"devices":[{"identifier":"WATCH-UDID-1","deviceProperties":{"name":"Test Watch"},"connectionProperties":{"transportType":"wifi","tunnelState":"connected"}}]}}
JSON
    cat >"$STUB_ROOT/xcrun" <<STUB
#!/bin/bash
if [[ "\$1" == "devicectl" && "\$2" == "list" && "\$3" == "devices" ]]; then
    cp "$WATCH_FIXTURE" "\$5"
    exit 0
fi
echo "\$*" >>"$STUB_ROOT/xcrun.log"
exit 0
STUB
    chmod +x "$STUB_ROOT/xcrun"
}

run_watch_installs_and_launches_resolved_device() {
    stub_watch_command
    mkdir -p "$STUB_ROOT/dd/Build/Products/Debug-watchos/CheckStitchWatch.app"
    DERIVED_DATA="$STUB_ROOT/dd" WATCH_NAME="Test Watch" bash scripts/run-watch.sh >/dev/null 2>&1 || return 1
    grep -q 'device install app --device WATCH-UDID-1' "$STUB_ROOT/xcrun.log" || return 1
    grep -q 'process launch.*app.alanvardy.CheckStitch.watchkitapp' "$STUB_ROOT/xcrun.log"
}

run_watch_errors_on_unreachable_device() {
    stub_watch_command
    cat >"$WATCH_FIXTURE" <<'JSON'
{"result":{"devices":[{"identifier":"WATCH-UDID-1","deviceProperties":{"name":"Test Watch"},"connectionProperties":{"transportType":null}}]}}
JSON
    local out status
    set +e
    out="$(DERIVED_DATA="$STUB_ROOT/dd" WATCH_NAME="Test Watch" bash scripts/run-watch.sh 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"Could not resolve"* ]]
}

run_watch_errors_on_unknown_device() {
    stub_watch_command
    local out status
    set +e
    out="$(DERIVED_DATA="$STUB_ROOT/dd" WATCH_NAME="No Such Watch" bash scripts/run-watch.sh 2>&1)"
    status=$?
    set -e
    [[ $status -ne 0 ]] || return 1
    [[ "$out" == *"Could not resolve"* ]]
}

run_watch_matches_typographic_device_name() {
    stub_watch_command
    mkdir -p "$STUB_ROOT/dd/Build/Products/Debug-watchos/CheckStitchWatch.app"
    # The real watch name carries a typographic apostrophe and a non-breaking
    # space; the CLI's ASCII default must still resolve it. JSON \u escapes
    # keep the fixture readable on disk.
    printf '%s\n' '{"result":{"devices":[{"identifier":"WATCH-UDID-CURLY","deviceProperties":{"name":"Alan\u2019s Apple\u00a0Watch"},"connectionProperties":{"transportType":"localNetwork","tunnelState":"disconnected"}}]}}' >"$WATCH_FIXTURE"
    DERIVED_DATA="$STUB_ROOT/dd" WATCH_NAME="Alan's Apple Watch" bash scripts/run-watch.sh >/dev/null 2>&1 || return 1
    grep -q 'device install app --device WATCH-UDID-CURLY' "$STUB_ROOT/xcrun.log"
}

run_case run_watch_installs_and_launches_resolved_device run_watch_installs_and_launches_resolved_device
run_case run_watch_errors_on_unreachable_device run_watch_errors_on_unreachable_device
run_case run_watch_errors_on_unknown_device run_watch_errors_on_unknown_device
run_case run_watch_matches_typographic_device_name run_watch_matches_typographic_device_name

echo "tests: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
