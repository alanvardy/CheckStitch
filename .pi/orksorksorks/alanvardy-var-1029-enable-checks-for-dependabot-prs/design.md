# Design Discussion

## Current State

- **CheckStitch has zero in-repo CI.** No `.github/`, no workflow, no dependabot
  config (confirmed: `ls -a` repo root; research.md Q4). The only CI is Xcode
  Cloud, configured entirely out-of-repo (`docs/TestFlight-xcode-cloud.md:4,
  :44-47, :115-116`). Every PR currently shows zero checks.
- **The gate is the single source of truth for "done"**: `bash scripts/test.sh`
  prints `gate: ok` (`scripts/test.sh:109`) after, in order, destination
  resolution (`:17-33`) → `make build` (`:35`) → host simulator lock
  (`:44-67`) → pre-boot `simctl boot`/`bootstatus` (`:90-93`) → `make test`
  (`:95`) → `make build-mac` → `make watch-build` (`:89-95`) → shell suite
  (`:110-112`) → shellcheck or `bash -n` fallback (`:113-119`).
- **Most of the gate is host-window machinery, not verification.** `.simulator_id`
  (`:19-24`, gitignored: `.gitignore:13-14`), the `$TMPDIR` lock with stale-PID
  reaping (`:41-64`), the `osascript` Simulator quit (`:80`), and the scoped
  `simctl shutdown` EXIT trap (`:69-71`) all exist so local agents don't wedge
  shared simulators. A hosted runner needs none of it.
- **`resolve-sim-udid.sh --require-id` refuses non-`id=` destinations**
  (`scripts/resolve-sim-udid.sh:13-18, :26-30`), so any `SIM=` value that isn't
  a pinned UDID yields `GATE_UDID=""` and the gate silently degrades to no
  pre-boot / no shutdown (`scripts/test.sh:83-84, :90-93`).
- **The genuinely portable legs** are `make build` (with a destination that
  exists), `make test-unit` (macOS host, `CODE_SIGNING_ALLOWED=NO`,
  `-only-testing:CheckStitchTests`, `Makefile:64-72`), `make build-mac`
  (unsigned, `Makefile:30-37`), `make watch-build` (`generic/platform=watchOS
  Simulator`, `Makefile:50-55`), `bash scripts/tests/run.sh` (fully stubbed host
  tools, `scripts/tests/run.sh:20-98`), and `shellcheck scripts/*.sh
  scripts/tests/*.sh` (`scripts/test.sh:113-119`).
- **`make test` is not usable as-is**: it is `test-unit` + `test-ui`
  (`Makefile:60-62`), and `test-ui` needs a concrete `$(SIM)` for
  `build-for-testing` / `test-without-building` (`Makefile:75-86`). There is no
  gate flag to skip it (only `GATE_TESTS_SKIP`, `scripts/test.sh:110`).
- **Signing is already off for the macOS legs** (`CODE_SIGNING_ALLOWED=NO`,
  `Makefile:36, :70`); `build-mac-signed` is the only target needing a profile
  (`Makefile:40-47`). Simulator/watch builds don't sign.
- **Deployment targets force a recent toolchain**: `IPHONEOS_DEPLOYMENT_TARGET
  = 18.7`, `MACOSX_DEPLOYMENT_TARGET = 27.0`, `WATCHOS_DEPLOYMENT_TARGET = 26.0`,
  `SWIFT_VERSION = 6.0` (`CheckStitch.xcodeproj/project.pbxproj:409-419,
  :474-482`). The macOS 27 target requires the **macOS 27 SDK, i.e. Xcode 27**;
  the local toolchain is `Xcode 27.0`. SingleThread's `macos-26` +
  `xcode-version: '26.6'` precedent (`SingleThread/.github/workflows/ci.yml:12,
  :23-26`) **cannot** build this repo's macOS leg.
- **shellcheck is not preinstalled on `macos-26`** (it is only on the Ubuntu
  images), so the gate's `bash -n` fallback (`scripts/test.sh:117-119`) would
  silently be the CI lint unless the workflow installs it.
- **Sibling precedent for shape only**: SingleThread's workflow is `push`-only
  (`ci.yml:3-5`) — it has no `pull_request` trigger and no actor gating, so
  nothing there can be copied for the "dependabot-only" requirement. Its
  `dependabot.yml` (`:1-13`, `github-actions` ecosystem, weekly, reviewer
  `alanvardy`, limit 5) is the config precedent.

## Desired End State

Two committed files, and nothing else:

1. `.github/workflows/dependabot-checks.yml` — one workflow, one job, that runs
   **only** on dependabot-authored pull requests and executes the portable gate
   legs in gate order:
   `make build` → `make test-unit` → `make build-mac` → `make watch-build` →
   `bash scripts/tests/run.sh` → `shellcheck scripts/*.sh scripts/tests/*.sh`.
2. `.github/dependabot.yml` — `github-actions` ecosystem, weekly, so dependabot
   PRs actually exist for the workflow to fire on.

**Correct when:**
- A dependabot PR (e.g. an action-version bump from the new `dependabot.yml`)
  shows a green `Dependabot checks / gate` check.
- A human PR shows **no check run** for this workflow other than a `Skipped`
  row (the accepted cost of `2A`); no leg ever executes.
- A deliberately broken commit pushed onto a dependabot branch turns the check
  red on the offending step, so the gate is real and not a no-op.
- CI is provisioning-free: no secrets, no `DEVELOPMENT_TEAM`, no
  `.simulator_id`, no lock, no `Simulator.app`.

**Local verification before pushing:** run the exact six-step sequence with
`SIM='generic/platform=iOS Simulator'` and `DEVELOPMENT_TEAM=` in the
environment (see Decisions 3–4), which should reproduce CI on a clean
`DerivedData`. **Post-merge verification is mandatory** — see Open Risks.

## Patterns to Follow

- **Gate order, leg-for-leg**: the workflow's step order copies
  `scripts/test.sh:35, :89-95, :110-119`, minus the host-bound parts. Reviewers
  should be able to diff steps against the gate by eye.
- **Unsigned macOS legs**: `make build-mac` / `make test-unit` already carry
  `CODE_SIGNING_ALLOWED=NO` (`Makefile:36, :70`) — use those targets, never
  `build-mac-signed` (`Makefile:40-47`).
- **`-only-testing` scoping stays Makefile-side** (`Makefile:70`, `:85`) — do
  not re-specify test scoping in YAML.
- **Runner/tool setup idiom from SingleThread**: `actions/checkout@v4`,
  `maxim-lobanov/setup-xcode@v1`, and `echo "DEVELOPMENT_TEAM=" >> $GITHUB_ENV`
  (`SingleThread ci.yml:21, :23-26, :28-29`) — but with the Xcode version this
  repo actually needs (Decision 4).
- **`generic/` destinations for compile-only legs**: `make watch-build` already
  uses `generic/platform=watchOS Simulator` (`Makefile:7, :50-55`); the iOS
  build uses the same idea via `SIM='generic/platform=iOS Simulator'`.
- **Gate lint is shellcheck, with a `bash -n` fallback**
  (`scripts/test.sh:113-119`): CI must install shellcheck so lint is strict.
- **`scripts/tests/run.sh` is CI-safe by construction** (stubbed
  `make/xcrun/defaults/open/osascript` on a temp `PATH`,
  `scripts/tests/run.sh:20-34, :87-98`) — no new isolation needed.
- **Same-repo script mode**: `scripts/*.sh` are `#!/bin/bash` + `set -euo
  pipefail` + mode `100755` (repo AGENTS.md) — match that style if any helper is
  added (none is planned).
- **Patterns NOT to follow**: (a) SingleThread's `xcode-version: '26.6'` — the
  repo needs Xcode 27 (Decision 4). (b) SingleThread's simulator pre-boot
  (`simctl list | grep` + `boot || true`, `ci.yml:39-43`) — there is no
  simulator touch in the selected legs, so copying it adds a false dependency on
  a device name. (c) The gate's `.simulator_id`/lock/`osascript` machinery —
  host-window concerns only. (d) A bare `name=` destination — rejected by
  `--require-id` and prone to image drift.

## Design Decisions

1. **Trigger and gate condition** (`2A`): `on: pull_request` with a job-level
   `if: github.event.pull_request.user.login == 'dependabot[bot]'`. `pull_request`
   is required for status checks; a job `if` is the only way to scope to
   dependabot, since `branches:` filters the **base** branch and there is no
   head-ref filter. Keying on `pull_request.user.login` (the PR author) rather
   than `github.actor` stays correct after `@dependabot rebase`, human-pushed
   synchronizes, and reopens. Accepted cost: non-dependabot PRs get one
   `Skipped` row and no executed check.
2. **Invocation shape** (`1B`): the workflow composes make targets directly;
   `scripts/test.sh` is untouched. The gate's portable legs are exactly
   `make` targets plus two plain commands, so a wrapper would add a third
   gate-like surface for no isolation benefit. Drift risk is contained by
   keeping step order and names aligned with `scripts/test.sh` and by the
   end-to-end verification above. It also avoids running `make test` (which
   would drag in `test-ui`) without adding a `GATE_UI_SKIP` knob to the gate.
3. **iOS build destination** (`3A`): `SIM: generic/platform=iOS Simulator` via
   job `env`. Compile-only against the simulator SDK, so no device-name
   dependency and no `--require-id` path; also keeps the whole run free of
   `simctl`. Passed as `SIM=` to `make build` (`Makefile:4-5, :17-24`).
4. **Xcode selection** (new, forced by `MACOSX_DEPLOYMENT_TARGET = 27.0`):
   `runs-on: macos-26` (the current image; `macos-27` is not assumed) **plus an
   explicit Xcode 27 selection and an assertion**. Xcode 27 is on the image as a
   public preview, so the step first lists `/Applications/xcode*` and then
   selects the 27.x app, and a guard step fails fast unless
   `xcodebuild -version` reports 27.x and the macOS 27 SDK is present. Pinning
   is required because the image default is not guaranteed to be 27; the exact
   app name/version string is resolved on the first run (Open Risks). Only if
   `macos-26` proves unable to provide Xcode 27 do we fall back to pinning
   `macos-26` + `setup-xcode` with an explicit 27.x version spec.
5. **Lint and caching** (`4A`): `brew install shellcheck` runs before the lint
   step so step 7 is real shellcheck, never the `bash -n` fallback
   (`scripts/test.sh:117-119`). **No** `actions/cache` for `DerivedData`: no
   cache to corrupt, no cross-run state to reason about, and dependabot runs are
   infrequent.
6. **Signing off**: job `env` carries `DEVELOPMENT_TEAM` empty (per
   SingleThread `ci.yml:28-29`) in addition to the Makefile's existing
   `CODE_SIGNING_ALLOWED=NO` for the macOS legs. No secrets are used anywhere,
   which also means the read-only token and withheld secrets on
   dependabot-triggered runs are irrelevant.
7. **One job, sequential steps**: a single job keeps one `DerivedData` and one
   toolchain-selection cost, mirrors `scripts/test.sh`'s ordering semantics, and
   produces one check for the dependabot PR. Per-leg parallelism is not worth
   the duplicated setup for a repo with no other CI.
8. **Dependabot config** (`5B`): `.github/dependabot.yml` mirroring SingleThread
   (`ci.yml:1-13`) — `version: 2`, `github-actions` ecosystem, `directory: "/"`,
   weekly Monday 08:00 `America/Vancouver`, reviewer `alanvardy`,
   `open-pull-requests-limit: 5`.
9. **Hygiene**: `permissions: contents: read`, `concurrency: {group:
   dependabot-checks-${{ github.ref }}, cancel-in-progress: true}`, and a
   generous `timeout-minutes` (45) so a wedged xcodebuild cannot burn the
   default six hours.
10. **Action pinning style**: floating major tags (`actions/checkout@v4`,
    `setup-xcode@v1`) so the new `github-actions` dependabot ecosystem has
    something to update — same convention as SingleThread (`ci.yml:21-26`).

## What We're NOT Doing

- **No UI tests.** `make test-ui` / `CheckStitchUITests` (`Makefile:75-86`) are
  excluded; they need a real simulator and are the flakiest leg on virtualized
  runners. The task's leg list omits them.
- **No gate changes.** `scripts/test.sh`, `scripts/tests/run.sh`, the Makefile,
  and the schemes are untouched — no `GATE_UI_SKIP`, no CI branch inside the
  gate.
- **No host-simulator machinery in CI**: no `.simulator_id`, no
  `resolve-sim-udid.sh`, no `$TMPDIR` lock, no `osascript`, no `simctl boot` /
  `bootstatus` / `shutdown`.
- **No signed or device legs**: no `build-mac-signed` (`Makefile:40-47`), no
  `scripts/run-devices.sh`, no `scripts/run-watch.sh`, no `devicectl`.
- **No branch protection / required checks** configuration, and no attempt to
  make the workflow fire on non-dependabot PRs.
- **No other CI features**: no DerivedData caching, no artifact/`.xcresult`
  upload, no matrix, no secret scanning (SingleThread's gitleaks job), no
  `push`/`schedule`/`workflow_dispatch` triggers, no Xcode Cloud changes, no
  TestFlight/release automation.
- **No changes to `docs/`** describing Xcode Cloud unless the workflow name or
  reality contradicts it.

## Open Risks

1. **Xcode 27 on the runner is the biggest unknown.** Xcode 27 is a public
   preview on `macos-26`, so the app name/version string is unverified; the
   guard step turns a wrong guess into a fast, obvious failure rather than a
   confusing SDK error. If Xcode 27 is unavailable there, the whole workflow
   cannot build the macOS leg, and the fallback is to gate the macOS leg on SDK
   availability or re-scope it — a design change, not a tweak.
2. **Post-merge-only verification for dependabot PRs.** Dependabot-triggered
   `pull_request` runs use the workflow definition from the base repo, so the
   workflow must be on `main` before any dependabot PR can exercise it. The
   first real dependabot PR is therefore the acceptance test; a temporary
   "break a step on the dependabot branch" check should confirm the gate is not
   silently skipping.
3. **`generic/platform=iOS Simulator` + `make build`.** Compile-only builds with
   a generic destination are normally fine (`make watch-build` already does
   this), but the `CheckStitch` scheme carries testables
   (`CheckStitch.xcscheme:32-53`), so the first run must confirm xcodebuild
   accepts the generic destination for the `build` action. Fallback: a
   `name=`-pinned device verified present on the image — never a bare `name=`
   left unreviewed.
4. **Runner image drift.** Device names, Xcode preview app names, and even the
   `macos-26` label contents change weekly; the shellcheck install and the Xcode
   guard are the two steps most likely to need occasional adjustment.
5. **`brew install shellcheck` latency/flakiness** adds tens of seconds and a
   network dependency to every dependabot run; if it proves unreliable, the
   accepted degradation is the gate's own `bash -n` fallback.
6. **Skipped-row semantics** are GitHub UI behaviour, not something the workflow
   controls: if the owner later decides "zero entries" is required, that needs
   branch-protection or event-shape redesign, not a YAML tweak — surfaced here
   so it is not discovered late.
7. **Dependabot PR throughput**: with `open-pull-requests-limit: 5` and weekly
   checks, multiple PRs can rebase concurrently; `cancel-in-progress`
   (`concurrency`) is what keeps runs from piling up.
