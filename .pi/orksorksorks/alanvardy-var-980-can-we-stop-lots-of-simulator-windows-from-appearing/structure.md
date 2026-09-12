# Structure Outline

## Approach

Stop `Simulator.app` from auto-attaching a window by asserting a per-host
`com.apple.iphonesimulator` preference, and make every simulator lifecycle use
one **headless pre-boot of this worktree's own UDID** with a scoped
trap-shutdown. `make run` re-opens the window explicitly, pinned to that UDID.
All layers are shell: a shared UDID resolver, a preference check/fix helper,
then the two consumers (`scripts/test.sh`, `scripts/run-simulator.sh`).

**Verification style for shell layers.** The repo has **no shell unit harness**
today (only `shellcheck`/`bash -n` inside the gate). We add a tiny
`scripts/tests/run.sh` assertion runner (plain bash, `set -euo pipefail`) and
call it from `scripts/test.sh` before `gate: ok`. Every stage below is green on
that runner plus the live gate. This runner is also where cross-cutting pieces
are **stubbable** (fake `xcrun`, fake `defaults` on `PATH`) — needed because the
gate's real behaviour can only be observed on a live host.

**Cross-cutting note (can't be a lower layer).** The windowing mechanism itself
(Decision 1) is a host observation, not unit-testable: if the preference has no
effect on Xcode 26.6, no amount of stubbing proves it. Stage 1 therefore carries
the spike **and** the helper that makes the *consequence* (gate asserts the
precondition) unit-testable. If the spike fails, Decision 6 (Stage 4b) is the
approved fallback — decide before Stage 3, do not fake the guarantee.

---

## Stage 1: Host windowless-preference helper + spike

Deliver `scripts/sim-windowless.sh` with `check`/`fix` subcommands over the
`com.apple.iphonesimulator AutoOpenDevice` preference, and record the spike
result (set → verify → boot → observe) proving the pref suppresses the window
with `Simulator.app` running.

**Files**: `scripts/sim-windowless.sh` (new, `100755`), `scripts/tests/run.sh` (new), `AGENTS.md` (setup note)

**Key changes**:
- `sim-windowless.sh check` — exits 0 when `defaults read com.apple.iphonesimulator AutoOpenDevice` is `0`; on failure prints the exact `fix` command to stderr and exits non-zero.
- `sim-windowless.sh fix` — writes the pref; **not** called by the gate.
- `windowless_pref_ok(): bool` — internal predicate, sourceable by tests via a stubbed `defaults`.

**Tests**: `scripts/tests/run.sh` cases `check_reports_ok_when_pref_false`, `check_reports_fix_when_pref_missing_or_true` (sad path) using a PATH-stubbed `defaults`.
**Verify**: `bash scripts/tests/run.sh` green; `bash scripts/test.sh` green; manual spike — with `Simulator.app` open and pref set, `xcrun simctl boot <own UDID>` opens **no** window. Record result here; if it fails, jump to Stage 4b.

---

## Stage 2: Shared UDID resolver

Factor `run-simulator.sh:20-28`'s `,id=`/`,name=` resolution into one script so
`scripts/test.sh` can resolve the same worktree UDID without a second resolver.

**Files**: `scripts/resolve-sim-udid.sh` (new, `100755`), `scripts/run-simulator.sh`, `scripts/tests/run.sh`

**Key changes**:
- `resolve-sim-udid.sh <destination>` — prints UDID on stdout, exits 1 with `ERROR: could not resolve a simulator for '<dest>'` otherwise (unchanged message).
- `run-simulator.sh` — replaces inline block with a call; no behaviour change. If `.simulator_id` is absent (destination degrades to shared `name=iPhone 17`) the caller must be able to detect "not our own device" — resolver gains an optional `--require-id` flag that fails when the destination is not an `,id=` form.

**Tests**: `resolves_id_form_directly`, `resolves_name_form_from_simctl_list`, `errors_on_unknown_name` (sad path), `require_id_rejects_name_form` (sad path) — stubbed `xcrun`.
**Verify**: `bash scripts/tests/run.sh` green; `bash scripts/test.sh` green (existing `make run` path unchanged).

---

## Stage 3: Gate pre-boot + scoped trap-shutdown

`scripts/test.sh` asserts the host precondition, pre-boots this worktree's UDID
headlessly between `make build` and `make test`, and trap-shuts it down on exit
— strictly scoped, never `all`/`booted`.

**Files**: `scripts/test.sh`, `scripts/tests/run.sh`, `AGENTS.md`

**Key changes**:
- Gate order: `make build` → `sim-windowless.sh check` (warn, don't hard-fail) → resolve UDID (`--require-id`) → `simctl boot "$UDID" || true` + `bootstatus "$UDID" -b` → `make test` → `shellcheck`/`bash -n` → `gate: ok`.
- `trap 'xcrun simctl shutdown "$UDID"' EXIT` — installed only after a UDID resolves; **no-op/skip** when `.simulator_id` is missing (shared-device fallback must never be shut down).
- Stages 1 & 2 utilities consumed, not duplicated.

**Tests**: `run.sh` case `gate_skips_preboot_without_own_udid` and `gate_shuts_down_only_resolved_udid` (stubbed `xcrun`/`make`, asserts `shutdown all` never occurs). Existing gate remains the real check.
**Verify**: `bash scripts/test.sh` prints `gate: ok`; with `Simulator.app` open and two concurrent agents running the gate, `osascript`-counted Simulator windows stays flat; `xcrun simctl list devices booted` shows no leftover gate device.

---

## Stage 4: `make run` opens its own window explicitly

With auto-open suppressed, `run-simulator.sh` must request the window after
boot, pinned to this worktree's UDID (not whatever `Simulator.app` currently has
selected).

**Files**: `scripts/run-simulator.sh`, `scripts/tests/run.sh`

**Key changes**:
- After `bootstatus`, `open -a Simulator --args -CurrentDeviceUDID "$UDID"` (syntax confirmed/adjusted in the Stage 1 spike; fallback to `simctl` UI reveal if unsupported).
- Window request only on the `make run` path; **not** reachable from `scripts/test.sh`.

**Tests**: `run.sh` case `run_path_requests_window_for_resolved_udid` (stubbed `open` records the UDID; asserts no window request is made by the gate path).
**Verify**: `bash scripts/tests/run.sh` green; `bash scripts/test.sh` green; manual `make run` shows exactly one window for `.simulator_id`'s UDID.

---

## Stage 4b: Fallback lock (only if Stage 1 spike fails)

Approved Decision 6: short host-scoped `flock`, quit `Simulator.app`, run the
gate, release. Time-bounded so it degrades to a warning rather than serialising
agents. Same files as Stage 3; chosen instead of Stage 1's preference check.
**Verify**: concurrent gates complete within the timeout and windows stay flat.

---

## Stage 5: Documentation

Record the one-time host setup (`sim-windowless.sh fix`), the gate's guarantee,
and the `make run` behaviour in `AGENTS.md`; note the spike outcome and any
fallback in use. No code. **Verify**: `bash scripts/test.sh` still `gate: ok`; docs match observed behaviour.

---

## Testing Checkpoints

- After **1**: `bash scripts/tests/run.sh` green **and** the live spike proves the pref suppresses the window — otherwise stop and take Stage 4b.
- After **2**: resolver tests green; gate unchanged in behaviour (`gate: ok`).
- After **3**: gate `ok`, no window appears, no leftover booted device, concurrent agents unaffected.
- After **4**: `make run` yields exactly one window on the worktree UDID; gate still windowless.
- Never advance while the current stage's runner cases or the gate are red.