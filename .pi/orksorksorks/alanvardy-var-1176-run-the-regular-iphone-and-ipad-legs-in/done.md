# Done

- **Branch / head SHA**: `alanvardy-var-1176-run-the-regular-iphone-and-ipad-legs-in` @ `021525c`
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` (52 shell tests passed,
  0 failed; simulator build, macOS compile, watch compile, shellcheck all green).
  Ran twice: once on the pre-fix head (green but masked the blocker below) and
  once after the fix.
- **Review outcome**:
  - **Blocker fixed** — `scripts/run-devices.sh:272` used `SIM_${label^^}`, a
    bash 4.1+ expansion. The `r`/`rd` aliases run `./scripts/run-devices.sh`
    directly, so the shebang `/bin/bash` (macOS 3.2) is the real interpreter; on
    the simulator-resolution-failure path it emitted `bad substitution`, lost the
    hint, and exited 0, masking the failure. Replaced with an explicit
    `case "$label"` → `SIM_IPHONE`/`SIM_IPAD` mapping. Verified by reproducing the
    failure path under `/bin/bash` (now prints `set SIM_IPAD` and exits 1). The
    gate did not catch this because its shell tests use Homebrew bash 5 and
    `scripts_parse_under_system_bash` only does `bash -n` (a parse check).
  - Also removed the `DELETEME` placeholder (commit `a105fd2`) per the plan.
  - **Flagged, deliberately deferred** — `~/dev/dotfiles/fish/functions/rd.fish`
    sets `IOS_TARGET=duo`, which the new validation rejects (`must be 'sim' or
    'device'`); the alias added during this ticket is dead. Per instruction this
    is left as a manual item (no dotfiles change made).
  - **Design flag (plan-sanctioned, not changed)** — in sim mode a paired-but-
    unreachable Duo still `exit 1`s at discovery before the simulator legs run;
    the plan explicitly keeps the `UNREACHABLE_COUNT` branch, so this stands.
  - Optional nits not applied (out of the agreed scope): dead `SIM_TOTAL`;
    stale "Opt-in via IOS_TARGET=sim" comment; the renamed Duo test dropped the
    `Developer Mode off` assertion; `run_devices_sim_prefers_the_worktree_simulator`
    greps vacuously if `.simulator_id` is blank/corrupt.
- **Remaining manual items** (from `plan.md`; require real devices/simulators):
  - `IOS_TARGET=device bash scripts/run-devices.sh` restores the old all-physical
    behaviour.
  - `IOS_TARGET=sim RUN_MAC=0 RUN_WATCH=0 bash scripts/run-devices.sh` boots the
    resolved iPhone + iPad simulators, opens the Simulator window, builds,
    installs and launches on each, exits 0.
  - With a Duo paired: default run boots both simulators, installs/launches on
    the Duo, builds signed macOS and runs the physical watch leg.
  - With no Duo paired: exits 0 with the "no reachable physical iPhone Duo" note
    and still runs both sim legs, macOS and watch.
  - Fix or drop the `rd` alias (`IOS_TARGET=duo`) in dotfiles.
