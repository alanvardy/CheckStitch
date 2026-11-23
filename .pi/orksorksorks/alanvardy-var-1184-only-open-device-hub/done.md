# Done

- **What was built**: `scripts/sim-window.sh` now opens the device GUI at most
  once per process instead of once per simulator — the per-udid
  `devices://device/open?id=` deep link is gone (Device Hub lists every booted
  simulator on one window), with the older-Xcode `open -a Simulator --args
  -CurrentDeviceUDID` fallback preserved and the open still best-effort /
  non-fatal. Both callers (`make run` and the `run-devices.sh` simulator legs)
  stay coherent via the shared helper.
- **Commit SHA(s)**: `815e83f` (implementation + shell tests), `aee2da0`
  (AGENTS.md doc fix), pushed to `alanvardy-var-1184-only-open-device-hub`.
- **Verification**: `bash scripts/tests/run.sh` → `tests: 72 passed, 0 failed`
  (includes new cases `sim_window_opens_device_hub_once_per_process`,
  `sim_window_falls_back_to_simulator_app`, `sim_window_reports_failure_once`,
  `run_path_opens_device_hub_once`, `run_devices_sim_opens_device_hub_once`);
  `bash -n` on the three scripts → PARSE_OK (macOS bash 3.2);
  `shellcheck scripts/sim-window.sh scripts/run-devices.sh
  scripts/run-simulator.sh` → clean. Xcode gate/`scripts/test.sh` not run.
- **Reviewer findings**: no blockers. P2 doc inconsistency in `AGENTS.md` (stale
  deep-link description) fixed in `aee2da0`. Nits deferred/report-only: on older
  Xcode only the first simulator gets the `Simulator.app` fallback (intended per
  the once-per-process requirement); `run-devices.sh:348` is an unguarded call
  that relies on the helper always returning 0 (true today).
- **Remaining manual items**: GUI outcome cannot be asserted by shell tests — a
  human should confirm that running `r` (`scripts/run-devices.sh`) opens Device
  Hub **once** and shows both booted simulators, and that `make run` still shows
  its window. Run the full `bash scripts/test.sh` gate if a complete green gate
  is required for merge.
