# Implementation Summary

## Commits
| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `0f7bf8c` | walking skeleton — `.github/dependabot.yml` + workflow with trigger, dependabot `if:` guard, Select/Guard Xcode 27, `Build (macOS, unsigned)` |
| 2     | `dcd757a` | simulator + watchOS compile legs — `Build (iOS Simulator)` and `Build (watchOS Simulator)` in gate order |
| 3     | `0096521` | test suites leg — `Unit tests (macOS host)` (`make test-unit`) and `Shell suite` (`bash scripts/tests/run.sh`) |
| 4     | `68b8d3c` | lint leg — `Install shellcheck` (`brew install shellcheck`) + `Lint (shellcheck)` (strict, no `bash -n` fallback) |
| 5     | `47daa0a` | hardening — `permissions: contents: read`, concurrency group with `cancel-in-progress`, `timeout-minutes: 45`; final file matches plan.md Appendix A byte-for-byte |

(Plus setup commit `da1086a`: removed the `DELETEME` placeholder and committed the VAR-1029 artifact directory.)

## Automated Checks
- [x] YAML parses for both `.github/dependabot.yml` and `.github/workflows/dependabot-checks.yml` (Phases 1, 5)
- [x] `actionlint .github/workflows/dependabot-checks.yml` exits 0 (all phases, final shape)
- [x] Guard expression present: `if: github.event.pull_request.user.login == 'dependabot[bot]'`
- [x] `env DEVELOPMENT_TEAM= make build-mac` passes locally (Phase 1)
- [x] `env SIM='generic/platform=iOS Simulator' make build` passes on clean `DerivedData` (Open Risk 3 resolved — generic destination accepted)
- [x] `make watch-build` passes on clean `DerivedData`
- [x] Step order grep lists iOS → macOS → watchOS in line order; full 9-step order matches gate order
- [x] `make test-unit` passes locally (237 tests / 33 suites)
- [x] `bash scripts/tests/run.sh` passes locally and exits 0 (17 tests)
- [x] No test selector in YAML (`only-testing`/`test-ui`/`make test` absent)
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` passes locally
- [x] No `bash -n` fallback in CI
- [x] `permissions:` and `timeout-minutes: 45` present in final workflow
- [x] Full local six-step reproduction on clean `DerivedData` in CI order: all exit 0 (Phase 5)
- [x] Scope: `git diff --name-only` contains no `Makefile`, `scripts/`, `xcshareddata`, or `project.pbxproj` paths — only the two `.github/` files (plus committed `.pi/` artifacts)
- [x] `bash scripts/test.sh` prints `gate: ok` — run once during Phase 5 (~19 min); this single green run evidences both the Phase 1 and Phase 5 gate boxes in plan.md (same condition: files present, gate reads nothing from `.github/`)

## Manual Verification Items (from the plan)
- [ ] **P1** Commit and push the branch; open its PR. The branch PR is a **human** PR, so confirm GitHub shows the `Dependabot checks` workflow as a single `Skipped` entry and that **no** step executed. (PR #50 is already open as a draft on this branch.)
- [ ] **P1** Merge to `main` (rebase merge). Dependabot-triggered `pull_request` runs use the workflow definition from the base repo, so this step is mandatory before any dependabot PR can exercise it (design Open Risk 2).
- [ ] **P1** On `main`, open **Insights → Dependency graph → Dependabot → Check for updates** to force a github-actions PR immediately (otherwise wait for the weekly run).
- [ ] **P1** On the resulting dependabot PR, confirm exactly one check named `Dependabot checks / gate` runs and turns green, with the steps `Select Xcode 27`, `Guard Xcode 27 and macOS 27 SDK` and `Build (macOS, unsigned)` all executed (not skipped). Inspect the guard step log: `xcodebuild -version` reports 27.x and `macOS SDK version: 27.*`.
- [ ] **P1** **Kill criterion**: if no Xcode 27 exists on `macos-26`, the workflow fails in `Select Xcode 27` with the available bundle list. Stop; re-run `design`. Do not proceed to Phase 2.
- [ ] **P2** On the dependabot PR, the check is green and both new steps show as executed. Open the `Build (iOS Simulator)` step log and confirm xcodebuild accepted `-destination generic/platform=iOS Simulator`.
- [ ] **P2** If Open Risk 3 materialises (generic destination rejected), apply the `SIM` fallback and re-run locally before pushing. Do not leave a bare `name=` destination unreviewed. (Locally it did NOT materialise; CI confirmation is this item.)
- [ ] **P3** On the dependabot PR, both new steps execute and the check is green.
- [ ] **P3** **Not-a-no-op proof (design Open Risk 2):** push a deliberately broken commit onto the dependabot branch and confirm the check goes red on `Unit tests (macOS host)` (or `Shell suite`), not on a compile step; restore afterwards.
- [ ] **P4** On the dependabot PR the `Lint (shellcheck)` step log shows shellcheck output (and is **not** the `bash -n` fallback); confirm by searching the step log for a shellcheck run, not merely trusting the step name (design Open Risk 5).
- [ ] **P4** If `brew install shellcheck` proves flaky/slow, do not silently drop the step: surface it. The accepted degradation (per design Open Risk 5) is reverting to the gate's `bash -n` fallback, which is a design decision, not an inline tweak.
- [ ] **P5** On the dependabot PR, the check is green, total runtime is comfortably under 45 minutes (read the run duration from the check page), and all seven legs execute in gate order: iOS build → unit tests → macOS build → watch build → shell suite → shellcheck.
- [ ] **P5** Rebase/close the PR while a run is in flight (or push twice quickly) and confirm GitHub shows the earlier run cancelled rather than queued (concurrency `cancel-in-progress`).
- [ ] **P5** Confirm a human PR still shows only the `Skipped` row and never executes a step.

## Notes / Observations
- **Force-push on Phase 1 push**: the mandated rebase onto `origin/main` rewrote the already-pushed start commit, so the first push was non-fast-forward. The worker escalated; the parent verified the remote-only commit was exactly the superseded pre-rebase tip (`bbfc04b`) and authorized `git push --force-with-lease`. All later phases pushed fast-forward.
- Workflow ends with exactly one trailing newline (fixed while appending Phase 4 steps).
- Action tags stay floating (`actions/checkout@v4`) per the Phase 1 `github-actions` dependabot ecosystem contract.
- No out-of-plan changes anywhere: no `Makefile`/`scripts/`/scheme/pbxproj edits; Phase 5's diff-scope check passed.