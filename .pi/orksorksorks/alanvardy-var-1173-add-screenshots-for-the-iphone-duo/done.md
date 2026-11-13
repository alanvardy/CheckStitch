# Done

- **Branch / head SHA**: `alanvardy-var-1173-add-screenshots-for-the-iphone-duo` @ `fb80667`
  (`fix: validate DUO_POSE from flag and env, tighten Duo shell tests`; feature head before
  review was `c65d1a7`). Pushed to `origin` with `--force-with-lease` (no rebase conflicts —
  `main` was already an ancestor of HEAD).
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok` (simulator build, macOS leg,
  watchOS leg, `make test`, 53 shell tests, shellcheck). Directly re-run: `/bin/bash -n`,
  `shellcheck scripts/*.sh scripts/tests/*.sh` clean. No Swift warnings-as-errors break.
- **Review outcome**: one bounded `reviewer` pass found **no P0/P1 blockers**. Its two P2
  notes were addressed, and two optional items were also applied (user chose option [2]):
  - *Fixed* — `DUO_POSE` exported via the environment bypassed the pose validation; the
    flag and env now funnel through one `folded|book|open` check that exits 2 before any
    simulator work. A bare `--duo-pose` no longer trips `set -u`.
  - *Fixed* — `--display` shell assertions only matched any `xcrun` line; tightened to
    target the actual `simctl io … screenshot … --display <id> …iphone-duo-…` capture call.
  - *Optional, applied* — a `==> skipped: iphone-duo (no Duo runtime/device found)` summary
    line so a missing-runtime run is not a silent green.
  - *Dismissed* — reviewer's "`simctl io screenshot --display` unverified on hardware": the
    supervisor confirmed both `--display 1` and `--display=1` forms return `exit 0` with a
    valid PNG on a booted simulator, so this is not a risk.
- **Remaining manual items** (unchanged from `plan.md` / `implement.md`; cannot be verified
  statically on the Duo runtime):
  - Set the Device Hub hinge pose and run the three-invocation sweep across all six
    languages: `--duo-pose folded`, then `--no-build --no-install --duo-pose book`, then
    `--duo-pose open` — all four variant folders present, every size accepted.
  - Confirm the folded run's `iphone-duo-outer-portrait/1-main-dark.png` is 1398×2034 with
    the widened Duo card, and `iphone-duo-outer-landscape/1-main-dark.png` is genuinely
    rotated to 2034×1398 (else re-open design decision 4).
  - Confirm `book` → `inner-portrait` 2007×2853 (standard layout) and `open` →
    `inner-landscape` 2853×2007.
  - Confirm a run against an inventory without the Duo runtime prints the warning + the new
    skip summary and still exits 0.
