# Implementation Summary

## Commits
| Phase | Commit    | Description |
|-------|-----------|-------------|
| 1     | `5327f61` | Add the simulator leg behind `IOS_TARGET` (default stays `device`) |
| 2     | `466e430` | Flip the default to `sim` and narrow physical discovery to the Duo |

Both commits touch only `scripts/run-devices.sh` and `scripts/tests/run.sh`; no
`plan.md`, `implement.md` or `.pi/orksorksorks/` content was staged.

## Automated Checks
- [x] `make build` — BUILD SUCCEEDED (Phase 1)
- [x] `bash scripts/tests/run.sh` — Phase 1: 49 passed, 0 failed (existing `device`-default cases + 4 new `sim` cases)
- [x] `shellcheck scripts/run-devices.sh scripts/tests/run.sh` — exit 0 (Phase 1)
- [x] `IOS_TARGET=banana bash scripts/run-devices.sh` — exits non-zero with `IOS_TARGET must be 'sim' or 'device'` (Phase 1)
- [x] `bash scripts/tests/run.sh` — Phase 2 full updated case set: 52 passed, 0 failed
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` — exit 0 (Phase 2)
- [x] `./scripts/test.sh` — prints `gate: ok` (full gate, run once after Phase 2 committed)

## Deviations / Notes
- Phase 2 pinned the five pre-existing `run_devices_watch_*` cases with
  `IOS_TARGET=device` (test-only). Those cases ran `run-devices.sh` under the
  old physical default; under the new `sim` default the simulator leg attempted
  resolution/boot and three went red. Pinning restores their exact pre-Phase-2
  conditions. This was a necessary, in-scope test adaptation not spelled out in
  the plan's Phase 2 change list.

## Manual Verification Items (from the plan)
- [ ] Phase 1: `IOS_TARGET=device bash scripts/run-devices.sh` behaves exactly as today (physical phone/iPad/Duo, macOS, watch) — spot-check with `RUN_MAC=0 RUN_WATCH=0` against `DEVICES_JSON_IN`
- [ ] Phase 1: `IOS_TARGET=sim RUN_MAC=0 RUN_WATCH=0 bash scripts/run-devices.sh` boots the resolved iPhone and iPad simulators, opens the Simulator window, builds, installs and launches CheckStitch on each, and exits 0
- [ ] Phase 2: `bash scripts/run-devices.sh` with a Duo paired boots both simulators, installs/launches CheckStitch on each, installs/launches on the Duo, builds signed macOS and launches it, and runs the physical watch leg
- [ ] Phase 2: `bash scripts/run-devices.sh` with no Duo paired exits 0 with the "no reachable physical iPhone Duo" note, both simulator legs, macOS and watch still run
- [ ] Phase 2: `IOS_TARGET=device bash scripts/run-devices.sh` restores the old all-physical behaviour
