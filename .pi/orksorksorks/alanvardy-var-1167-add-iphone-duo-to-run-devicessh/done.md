# Done

- **Branch / head SHA**: `alanvardy-var-1167-add-iphone-duo-to-run-devicessh`,
  reviewed/pushed SHA `d68b8ae` (final docs-only `done.md` commit follows this
  marker). Pushed to `origin` with `--force-with-lease`. No rebase was in
  progress and no conflicts existed to resolve.

- **Mechanical checks**: `./scripts/test.sh` printed `gate: ok`,
  `tests: 44 passed, 0 failed` — `make build` (simulator) → headless simulator
  pre-boot → `make test` → `make build-mac` → `make watch-build` (watchOS) →
  `scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`.
  Standalone `shellcheck scripts/run-devices.sh scripts/run-watch.sh
  scripts/tests/run.sh` clean, and `bash scripts/tests/run.sh` re-run after the
  review fixes → exit 0, 44 passed, 0 failed. No warnings flagged.

- **Review outcome**: one bounded fresh-context `reviewer` over
  `git diff main...HEAD` (5 files, +527/−39), cross-checked against source by
  the supervisor.
  - **Blockers: one, fixed.** `DELETEME:1` was a committed placeholder whose
    own text says "git rm before merging" and which matches the repo's repeated
    `chore: remove DELETEME placeholder` history. Removed in `617ca9c` (with the
    step artifacts).
  - **Fixes worth doing now: none.** The reviewer found no functional,
    error-handling, or regression defect, and the supervisor's own scan agrees:
    the `reality != "physical"` filter, the Developer-Mode noted-not-skipped
    path, the per-device `-destination "id=<udid>" -allowProvisioningUpdates
    -allowProvisioningDeviceRegistration` build with per-device `continue`, and
    the watch exit-2 generic `.watchOS` fallback are sound, and the new shell
    cases genuinely pin them.
  - **Optional improvements: all three applied** (user chose `[2]`) in
    `d68b8ae`:
    1. `scripts/run-devices.sh` — simulator-exclusion comment no longer claims
       symmetry with a watch filter that does not exist (the watch resolver
       matches by name only).
    2. `scripts/run-devices.sh` — watch-step failure message no longer lists
       Developer Mode off as a cause (it is not one on the watch path).
    3. `scripts/run-watch.sh` — the unreachable-watch fallback no longer emits
       the contradictory "not found" + "the app was built" pair; each branch now
       states the outcome.

- **Remaining manual items** (from `plan.md` / `implement.md`; cannot close on
  static evidence — the gate/unit tests cannot install to real hardware):
  - Phase 1: `DEVICES_JSON_IN=scripts/fixtures/devicectl-devices.json RUN_MAC=0
    RUN_WATCH=0 bash scripts/run-devices.sh 2>&1 | grep Developer` prints the
    Developer-Mode-off notes for the iPad and the Duo, and no simulator device.
  - Phase 2: the same offline invocation's build lines name each of the three
    fixture devices (`-destination id=<udid>` per device).
  - Phase 2 (real hardware): a run against the real Duo completes without
    `0xe8008012`; proof is the install, not the script output.
  - Phase 3 (real hardware): the watch leg installs without a provisioning
    error; verify the installed bundle on the watch.
