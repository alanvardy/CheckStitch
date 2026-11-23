# Done

- **What was built**: Added an `IOS_TARGET=duo` mode to `scripts/run-devices.sh` so the dotfiles `rd` fish function (which hardcodes `IOS_TARGET=duo`) works: it deploys only to the physical iPhone Duo, skips the simulator legs, and defaults `RUN_MAC=0`/`RUN_WATCH=0` while an explicit `=1` opts each leg back in. Validation, discovery, the no-device branch and the header comment were updated, `scripts/tests/run.sh` gained two cases, and `AGENTS.md` documents the target.
- **Commit SHA(s)**: `79472fb` (implementation + tests + docs), `02f788b` (review nit fixes).
- **Verification**: `bash scripts/tests/run.sh` → `tests: 69 passed, 0 failed` (incl. `run_devices_duo_targets_only_the_duo_physically`, `run_devices_duo_run_mac_1_opts_back_in`); `bash -n` on both scripts; `shellcheck scripts/*.sh scripts/tests/*.sh ci_scripts/*.sh` → exit 0.
- **Reviewer findings**: no blockers. Two nits fixed in `02f788b`: the duo no-device message now reflects the actual `RUN_MAC`/`RUN_WATCH` flags instead of always claiming "macOS + Apple Watch run only", and the header override block notes the duo `0` defaults.
- **Remaining manual items**: none. `rd` in fish now resolves to `IOS_TARGET=duo ./scripts/run-devices.sh`, so the Duo-only flow can be exercised on hardware by the user.
