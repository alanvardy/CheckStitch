# Task

CheckStitch has no CI today (no `.github` directory, no workflows, no branch
protection checks). Dependabot is expected to open dependency-update PRs for
this repo, and no agent runs the project gate on those PRs, so GitHub
Actions must run the checks instead. Add a GitHub Actions workflow
(`.github/workflows/`) to CheckStitch that runs the build/test gate **only on
dependabot PRs** — for all other PRs, checks must continue not to run. The
workflow must be provisioning-free like the local gate and select the legs of
the `./scripts/test.sh` gate (simulator build, unit tests, macOS compile,
watchOS compile, shellcheck) that can run on a hosted macOS runner — no
per-worktree `.simulator_id`, no `Simulator.app` window management, no host
lock.