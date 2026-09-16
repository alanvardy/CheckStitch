# Task

CheckStitch has no CI at all today (no `.github` directory, no workflows, no
branch protection; every PR on the repo shows zero checks). Dependabot is
expected to open dependency-update PRs for this repo, and since no agent runs
the project gate on those PRs, GitHub Actions must run the checks instead.
Add a GitHub Actions workflow to CheckStitch that runs the build/test gate
**only on dependabot PRs** — for all other PRs checks must continue not to
run. The workflow lives in this repo (`.github/workflows/`), is provisioning-
free like the local gate (`make build-mac` and `make test-unit` already run
unsigned), and must select the right legs of the `./scripts/test.sh` gate
(simulator build, unit tests, macOS compile, watchOS compile, shellcheck) that
can actually run on a hosted macOS runner (no worktree-`.simulator_id`
mechanism, no `Simulator.app` window management, no host lock).

## Why LARGE

NEW_SURFACE (the repo's first CI integration — a new subsystem, not a
localized change), CONVENTION_RISK (touches build/CI config — the Makefile /
`scripts` gate — and must stay provisioning-free and correct across the
iOS/macOS/watchOS legs), UNKNOWNS (which gate legs are portable to a hosted
macOS runner and how the host-dependent `scripts/test.sh` pre-boot/lock logic
maps to GitHub Actions; how to trigger *only* dependabot PRs — `pull_request`
branch filters match the base branch, so a job-level `github.actor` /
`head_ref` condition is needed; which runner image/Xcode the project needs,
per the SingleThread ci.yml precedent using `macos-26` +
`maxim-lobanov/setup-xcode`; how signing is kept off CI), and DESIGN_SIGN-OFF
(full gate vs slimmed check set, and the trigger/condition shape are viable
design choices needing a decision).