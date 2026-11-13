# Task

Change `scripts/run-devices.sh` so the **regular iPhone and iPad legs run in the
simulator** instead of on paired physical hardware, while the physical
**iPhone Duo** and the **macOS** leg stay exactly as they are today. The Apple
Watch leg in this repo (physical, via `run-watch.sh`) is unchanged by this
ticket unless the plan finds it must move with the port.

Port the simulator-leg approach already implemented in
`/Users/vardy/dev/SingleThread/scripts/run-devices.sh` (referenced by the
ticket) onto CheckStitch's structure, deciding the simulator default and the
physical discovery filter in the plan. Update the shell tests in
`scripts/tests/run.sh` for the new default and the changed discovery filter (the
existing `run_devices_*` cases assume every physical device installs by
default), and adjust `scripts/fixtures/*` if a Duo product type / sim fixture is
needed.

Why: `run-devices.sh` currently requires a physically paired iPhone and iPad to
exercise those legs; moving them to simulators makes a normal dev run work
without hardware, leaving only the Duo and Mac as physical targets.

## Why MEDIUM

Matched breadth triggers **MULTI_MODULE** and **BROAD_TEST_SURFACE**: the change
spans `scripts/run-devices.sh` plus the `scripts/tests/run.sh` shell harness (and
likely fixtures), where the existing `run_devices_*` cases and stubs must be
reworked. M1 holds — the approach is known and a working reference
implementation exists (SingleThread, plus this repo's own
`scripts/resolve-sim-udid.sh` / `scripts/run-simulator.sh` patterns); M2 holds —
no schema/migration, no new subsystem or integration, no shared/convention code
and no trade-off needing sign-off. No LARGE design-class trigger applies.

## Key files (from recon)

- `scripts/run-devices.sh` (238 lines) — the script to change. Currently
  discovers all physical iPhone/iPad via `devicectl` and builds/installs/launches
  each; watch delegated to `run-watch.sh`; macOS via `make build-mac-signed`.
- `/Users/vardy/dev/SingleThread/scripts/run-devices.sh` (537 lines) — reference
  implementation: `IOS_TARGET=sim` default, `SIM_IPHONE`/`SIM_IPAD` overrides,
  `resolve_ios_udid`, `show_sim_window`, Duo-only physical filter, sim leg, and
  a summary block.
- `scripts/tests/run.sh` (836 lines) — shell tests run by the gate. Relevant:
  the run-devices watch-path cases (~lines 285–365) and the iOS discovery filter
  + destination cases (~lines 366–460, incl.
  `run_devices_discovers_every_physical_ios_device`). Stubs `xcrun`/`xcodebuild`/
  `make`/`open`.
- `scripts/fixtures/devicectl-devices.json` — fixture inventory (includes
  `Fixture iPhone Duo` with `iPhone19,4`, an iPad, and an iPhone Sim).
- `scripts/resolve-sim-udid.sh`, `scripts/run-simulator.sh` — existing
  simulator-resolution/boot patterns in this repo to reuse rather than
  reinventing.
- `scripts/test.sh` (gate) — `scripts/tests/run.sh` shell tests are part of the
  gate, so the updated cases must stay green.
