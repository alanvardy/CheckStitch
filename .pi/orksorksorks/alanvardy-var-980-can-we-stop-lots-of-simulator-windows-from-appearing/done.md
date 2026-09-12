# Done

- **Branch / head SHA**: `alanvardy-var-980-can-we-stop-lots-of-simulator-windows-from-appearing` @ review-fixes commit on top of `617e2c8` (branch level with `main`; working tree clean after this commit).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` after the fixes — real build, `make test`, `make build-mac`, **12/12 shell cases**, `shellcheck scripts/*.sh scripts/tests/*.sh` exit 0, script modes `100755`. No lock leak and no worktree device left booted after the gate. Only pre-existing warnings: macOS deployment-target 27.0 vs SDK 26.5 range.
- **Review outcome**: one fresh-context bounded `reviewer` pass over the pre-fix diff (`.pi/orksorksorks/…/review-diff.patch`, kept as the reviewed snapshot) → **no blockers**. Verdict: sound design for the stated goal (no Simulator windows during gates; `make run` pinned to the resolved UDID), correct `set -euo pipefail`/trap/lock mechanics, behaviour-preserving resolver extraction, and meaningful stub cases. User selected option [2] (fixes worth doing now **plus** optional improvements); all were applied, validated by the full gate, and committed.
- **Remaining manual items**: the `plan.md`/`implement.md` manual verification items (spike confirmation, `make run` single-window check, two-terminal concurrent-gate check) remain for the user.

## Applied fixes

1. **Repo hygiene**: `DELETEME` removed (`git rm`) and the untracked step artifacts (`conventions.md`, `design.md`, `large.md`, `questions.md`, `research.md`, `structure.md`, `task.md`) committed with `done.md` and `review-diff.patch`, matching prior tickets and AGENTS.md.
2. **Lock test** (`scripts/tests/run.sh`): `lock_times_out_instead_of_blocking` now runs the gate child under a private `TMPDIR` (so it can no longer `rmdir` a live concurrent gate's lock) and asserts the `simulator lock busy after 1s` warning, not just exit 0.
3. **Corrupt `.simulator_id`** (`scripts/resolve-sim-udid.sh`, `scripts/test.sh`): `--require-id` now rejects a non-UUID value with a clear message, and the gate fails fast when a present `.simulator_id` does not resolve instead of aborting later on a raw `xcrun` error. An explicit `SIM=` name-form destination still degrades to warning-and-skip.
4. **Stub temp-dir leak** (`scripts/tests/run.sh`): `new_stubs` reaps the previous stub tree before creating the next.
5. **Trailing newlines** added to `scripts/test.sh`, `scripts/resolve-sim-udid.sh`, `scripts/tests/run.sh`.

## Optional improvements applied

- `gate_shuts_down_only_resolved_udid` now asserts the window-suppression lever (`tell application "Simulator" to quit`) actually fired.
- Every gate child test runs with `env -u SIM`, so a caller's exported `SIM` cannot leak into the fixture.
- The lock is **released after `make test`** (the simulator-touching part) instead of only at exit; the EXIT trap remains the safety net. Stale locks left by a killed gate are now **reaped by recorded PID**.
- `AGENTS.md` "Simulator windows" updated to the exact behaviour (quit once before pre-boot, scoped lock release, stale-PID reaping, present-but-unresolvable `.simulator_id` is a hard error) and the `make run` `--args` fresh-launch caveat.

## New tests added

- `require_id_rejects_non_uuid` — resolver rejects a non-UUID `id=` destination in `--require-id` mode.
- `gate_errors_on_invalid_simulator_id` — gate fails fast with a clear message on a corrupt `.simulator_id`.
- `stale_lock_is_reaped` — a lock with a dead holder PID is reclaimed instead of waited out.
