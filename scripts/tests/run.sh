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