# Implementation Summary

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1 | `cd08e41` | discover every paired physical iPhone/iPad (offline fixture) |
| 2 | `4dbf574` | build per device so a newly paired iPhone auto-registers |
| 3 | `6f7e49e` | auto-register the Apple Watch with a generic build fallback |

All three commits are on `alanvardy-var-1167-add-iphone-duo-to-run-devicessh`
and pushed to `origin`. Each phase's commit contains only its own source/test
files (no `plan.md`, no `.pi/orksorksorks/` artifacts, no `DELETEME`).

## Automated Checks

- [x] Phase 1: `bash scripts/tests/run.sh` passes — `ok:` for
      `run_devices_discovers_every_physical_ios_device`,
      `run_devices_rejects_unreadable_saved_inventory`,
      `run_devices_rejects_malformed_saved_inventory`
- [x] Phase 1: `shellcheck scripts/run-devices.sh scripts/tests/run.sh` clean
- [x] Phase 1: `/bin/bash -n scripts/run-devices.sh` clean
- [x] Phase 2: `bash scripts/tests/run.sh` passes — `ok:` for
      `run_devices_builds_against_each_device_destination`,
      `run_devices_continues_after_a_device_build_failure`
- [x] Phase 2: `shellcheck scripts/run-devices.sh scripts/tests/run.sh` clean
- [x] Phase 3: `bash scripts/tests/run.sh` passes — all run-watch and
      run-devices-watch cases `ok:`
- [x] Phase 3: `shellcheck scripts/run-watch.sh scripts/tests/run.sh` clean
- [x] Phase 3: `/bin/bash -n scripts/run-watch.sh` clean
- [x] Full gate `./scripts/test.sh` prints `gate: ok` (44 passed, 0 failed) —
      run by the parent after all three phases landed

## Manual Verification Items (from the plan)

- [ ] Phase 1: `DEVICES_JSON_IN=scripts/fixtures/devicectl-devices.json RUN_MAC=0 RUN_WATCH=0 bash scripts/run-devices.sh 2>&1 | grep Developer` prints two Developer Mode-off notes (iPad + Duo) and no simulator device.
- [ ] Phase 2: `DEVICES_JSON_IN=scripts/fixtures/devicectl-devices.json RUN_MAC=0 RUN_WATCH=0 bash scripts/run-devices.sh 2>&1 | grep 'Building CheckStitch'` names each of the three fixture devices.
- [ ] Phase 2 (real hardware): a run against the Duo completes without `0xe8008012` (proof is the install, not the script output — see the `devicectl` skill).
- [ ] Phase 3: `./scripts/test.sh` prints `gate: ok` — confirmed by the parent run above; awaiting your confirmation.
- [ ] Phase 3 (real hardware): the watch leg installs without a provisioning error (verify the installed bundle on the watch — see the `devicectl` skill).

## Notes

- The `DELETEME` placeholder was found deleted in the working tree before Phase
  1. It was not part of this plan; it was restored to keep the tree clean and
  left untouched/uncommitted.
- No out-of-scope refactors or fixes were made. No blockers or plan mismatches
  were encountered.
