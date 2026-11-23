# Task

When running `r` (`scripts/run-devices.sh`, the developer's manual device/simulator
runner), the simulator legs currently open a separate Device Hub window per booted
simulator. Change the runner so it opens **Device Hub once** and shows the app on the
simulators there, instead of opening an individual window/deep link for each simulator.

Keep the existing Xcode-version behaviour intact: on Xcode 27 this is Device Hub
(`com.apple.dt.Devices`); on older Xcode it still uses `Simulator.app`. The window
open is a best-effort convenience and must stay non-fatal (a failure is reported, not
counted as a failed step). `make run` (`scripts/run-simulator.sh`) shares the same
window helper, so keep both callers coherent.

Linear: VAR-1184, project CheckStitch.

## Why SMALL

Single seam: the window helper `scripts/sim-window.sh` and its two callers, with local
shell-test updates. Approach is already established (the existing Device Hub/Simulator
fallback in `sim-window.sh`); no schema, no new subsystem, no shared-convention or
product trade-off, no design decision. Tests affected are a few local shell cases.

## Key files (if the recon found any)

- `scripts/sim-window.sh` — `show_sim_window <udid>`: `open -b com.apple.dt.Devices`
  then a per-udid `devices://device/open?id=$udid` deep link (Xcode 27), falling back
  to `open -a Simulator --args -CurrentDeviceUDID`. This is where the per-simulator
  window behaviour lives.
- `scripts/run-devices.sh` — simulator leg calls `show_sim_window "$udid"` once per
  simulator (~line 348); sources `sim-window.sh` at ~line 88.
- `scripts/run-simulator.sh` — `make run` path calls `show_sim_window "$UDID"` at
  ~line 61; sources the same helper.
- `scripts/tests/run.sh` — pins current behaviour and will need updating:
  `run_path_requests_window_for_resolved_udid` (~line 190, asserts the per-udid Device
  Hub deep link) and `run_devices_sim_opens_device_hub_windows` (~line 530, asserts the
  deep link opens for each simulator). Stubs `open` on PATH.

Note: the GUI outcome (Device Hub actually showing all booted simulators) cannot be
asserted by the shell tests — state what a human should see when reporting.
