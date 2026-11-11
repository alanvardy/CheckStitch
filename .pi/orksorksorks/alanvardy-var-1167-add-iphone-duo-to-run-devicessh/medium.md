# Task

Make `scripts/run-devices.sh` (and the watch leg it delegates to) actually
install and launch on **every** paired physical iPhone/iPad — including the
newly added "iPhone Duo" — in addition to the iPhone 16 Pro that already
receives builds.

The change is already implemented and proven in the sibling repo
`/Users/vardy/dev/SingleThread` (Linear VAR-1166). Port that shape to
CheckStitch:

1. **Discovery filter** — stop requiring Developer Mode to be already
   `enabled` at discovery time; a freshly paired second iPhone (the "Duo",
   `productType iPhone19,4`) is silently skipped every run after the phone is
   unlocked/promoted. Include every paired physical iPhone/iPad, and add the
   missing `reality == "physical"` guard so a booted iOS simulator is never
   treated as a devicectl install target (parity with the watch filter).
   devicectl already reports the real install failure and a note should name
   the likely cause.
2. **Per-device build** — the single `-destination 'generic/platform=iOS'`
   build has no destination device, so `-allowProvisioningUpdates` never
   registers a newly paired phone and its install fails with `0xe8008012`
   ("This provisioning profile cannot be installed on this device"). Build
   each device against `-destination "id=<udid>"` with
   `-allowProvisioningUpdates -allowProvisioningDeviceRegistration`. The first
   device compiles; the rest only re-sign against the shared team profile.
3. **Apple Watch leg** — CheckStitch delegates the watch to
   `scripts/run-watch.sh`, which still uses
   `-destination 'generic/platform=watchOS'` without
   `-allowProvisioningDeviceRegistration`. Apply the same per-device /
   auto-registration treatment (with the generic build kept as the fallback
   when only an unreachable watch is present).
4. **Tests/fixture** — port the devicectl inventory fixture and the offline
   filter checks so the Duo-with-Developer-Mode-off and the simulator-excluded
   cases are covered in `scripts/tests/run.sh`.

Reference implementation (do not edit these; read as the pattern):
- `/Users/vardy/dev/SingleThread/scripts/run-devices.sh`
- `/Users/vardy/dev/SingleThread/scripts/test-run-devices.sh`
- `/Users/vardy/dev/SingleThread/scripts/fixtures/devicectl-devices.json`
- Commits `6895892a` ("install on the iPhone Duo") and `7836a415`
  ("auto-register each device so a new iPhone installs").

## Why MEDIUM

M1/M2 hold: approach is known (a working reference exists in SingleThread —
no new technology, no schema/migration, no new subsystem, no design decision
or human sign-off, no shared/gate code changed). Breadth triggers apply —
MULTI_MODULE (10): `run-devices.sh` + `run-watch.sh` + shell tests + a new
fixture; BROAD_TEST_SURFACE (11): the build/signing path is shared and the
filter cases need offline fixture coverage. Hence too broad for one pass but
not design-class.

## Key files

- `scripts/run-devices.sh` — discovery filter (lines ~54–111), the single
  generic iOS build + install loop (lines ~118–165).
- `scripts/run-watch.sh` — `-destination 'generic/platform=watchOS'` build
  (lines ~85–95), watch-name resolution.
- `scripts/tests/run.sh` — stubbed `xcrun devicectl list devices` fixtures;
  run-devices.sh and run-watch.sh shell cases (lines ~205–350); the gate runs
  this file plus `shellcheck`.
- `scripts/fixtures/` — needs a `devicectl-devices.json` inventory fixture
  alongside the existing `appstore-seed.json`.
- `/Users/vardy/dev/SingleThread/scripts/` — reference scripts and commits
  above.
