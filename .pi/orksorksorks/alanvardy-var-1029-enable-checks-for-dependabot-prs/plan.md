# Implementation Plan

## Overview

Ship two committed files — `.github/dependabot.yml` (so dependabot PRs exist)
and `.github/workflows/dependabot-checks.yml` (one job, `pull_request` +
dependabot-author `if`, running the portable legs of `scripts/test.sh` in gate
order, provisioning-free) — and nothing else. No app code, no Makefile, no
`scripts/`, no scheme changes. Slicing is by **which real gate leg executes on a
dependabot PR**: Phase 1 lands the walking skeleton (`make build-mac`), Phase 2
adds the two remaining compile legs, Phase 3 adds the test suites, Phase 4 makes
lint real (shellcheck, not `bash -n`), Phase 5 hardens.

**Files touched across all phases (complete list):**

| File | Action |
|---|---|
| `.github/dependabot.yml` | create (Phase 1) |
| `.github/workflows/dependabot-checks.yml` | create (Phase 1, extended in 2–5) |

The complete final workflow is reproduced in **Appendix A**; every non-trivial
snippet below is byte-for-byte compatible with it.

**Reference constants** (from `conventions.md`; do not re-derive):
- Gate leg order (`scripts/test.sh`): `make build` → `make test` →
  `make build-mac` → `make watch-build` → `bash scripts/tests/run.sh` →
  shellcheck (or `bash -n` fallback).
- Unsigned legs already carry `CODE_SIGNING_ALLOWED=NO` (`Makefile:36, :70`).
- `SIM` is consumed by `make build` (`Makefile:4-5, :17-24`); the watch leg uses
  its own fixed generic destination (`Makefile:7, :50-55`).
- Sibling precedent: `SingleThread/.github/dependabot.yml` and
  `SingleThread/.github/workflows/ci.yml:3-9, :18-29`.
- Xcode 27 is required by `MACOSX_DEPLOYMENT_TARGET = 27.0`
  (`CheckStitch.xcodeproj/project.pbxproj`).

**Global acceptance (all phases):** a real dependabot PR shows one executed
green `Dependabot checks / gate` check; a human PR shows only a `Skipped` row;
a deliberately broken commit on a dependabot branch turns the check red on the
offending step; CI uses no secrets, no `DEVELOPMENT_TEAM`, no `.simulator_id`,
no lock, and no `Simulator.app`.

---

## Phase 1: Walking skeleton — a dependabot PR runs a real check

### Changes

#### 1. `.github/dependabot.yml` (new)

Creates the source of dependabot PRs. Mirror `SingleThread/.github/dependabot.yml`
exactly (github-actions ecosystem, weekly, reviewer, limit 5).

```yaml
version: 2
updates:
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
      day: monday
      time: "08:00"
      timezone: America/Vancouver
    reviewers:
      - "alanvardy"
    open-pull-requests-limit: 5
```

#### 2. `.github/workflows/dependabot-checks.yml` (new)

Phase 1 creates the full skeleton with the cheapest real portable leg
(`make build-mac`), plus the trigger, the dependabot guard, the Xcode 27
selection, and the guard assertion. **Do not add hardening keys (Phase 5) or
later legs (Phases 2–4) yet.**

```yaml
name: Dependabot checks

on:
  pull_request:

jobs:
  gate:
    if: github.event.pull_request.user.login == 'dependabot[bot]'
    runs-on: macos-26
    env:
      DEVELOPMENT_TEAM: ""
      SIM: generic/platform=iOS Simulator
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 27
        run: |
          set -euo pipefail
          for app in /Applications/Xcode*.app; do
            if [[ "$("$app/Contents/Developer/usr/bin/xcodebuild" -version 2>/dev/null | head -1)" == "Xcode 27."* ]]; then
              echo "Selecting $app"
              sudo xcode-select -s "$app/Contents/Developer"
              exit 0
            fi
          done
          echo "No Xcode 27.x found. Available Xcode bundles:" >&2
          ls -d /Applications/Xcode*.app >&2 || true
          exit 1

      - name: Guard Xcode 27 and macOS 27 SDK
        run: |
          set -euo pipefail
          xcodebuild -version
          xcodebuild -version | head -1 | grep -q '^Xcode 27\.' \
            || { echo "expected Xcode 27.x" >&2; exit 1; }
          sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
          echo "macOS SDK version: $sdk_version"
          [[ "$sdk_version" == 27.* ]] \
            || { echo "expected macOS 27 SDK, got: $sdk_version" >&2; exit 1; }

      - name: Build (macOS, unsigned)
        run: make build-mac
```

**Deliberate deviation from `structure.md` (Xcode selection mechanism):**
structure says `maxim-lobanov/setup-xcode@v1` with the pin resolved on first
run. This plan uses a discovery+select shell step instead, for three reasons:
(a) the runner image already ships Xcode 27 as a beta bundle whose exact name
drifts (`Xcode_27_beta_N.app` vs the stable-named symlinks) — a discovery loop
keys on the *version output*, not a bundle name or a guessed `xcode-version:`
spec, and returns a readable list on failure; (b) it avoids a network download
per run; (c) if the image genuinely lacks Xcode 27, adding `setup-xcode@v1`
cannot fix that either, and the guard step is what must fail fast. The
setup-xcode path is retained as the documented fallback below.

**Fallback if the Select step cannot find Xcode 27 (structure's kill
criterion):** per `structure.md`, **stop and re-run the `design` step** — do not
patch onward. The candidate design change is switching `runs-on:` from
`macos-26` to the `xcode-27` preview runner-image label (or, secondarily,
adding `maxim-lobanov/setup-xcode@v1` with an explicit `27.x` spec taken from
the runner image readme). Either is a one-line change to `runs-on`/a step, not
a step-shape change, but it is a design decision, not a Phase 1 tweak.

**Contract established here (all later phases inherit, none changes):** workflow
name `Dependabot checks`; job id `gate` → check-run name
`Dependabot checks / gate`; `on: pull_request`; job-level
`if: github.event.pull_request.user.login == 'dependabot[bot]'`; `runs-on:
macos-26`; job `env: { DEVELOPMENT_TEAM: "", SIM: "generic/platform=iOS Simulator" }`;
the Select-Xcode + Guard steps.

### Verification

#### Automated
- [x] `python3 -c "import yaml; yaml.safe_load(open('.github/dependabot.yml'))"` exits 0
- [x] `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/dependabot-checks.yml'))"` exits 0
- [x] `actionlint .github/workflows/dependabot-checks.yml` exits 0 (actionlint is installed locally at `/opt/homebrew/bin/actionlint`)
- [x] `grep -F "github.event.pull_request.user.login == 'dependabot[bot]'" .github/workflows/dependabot-checks.yml` prints the `if:` line (guard expression assertion)
- [x] `grep -F 'Build (macOS, unsigned)' .github/workflows/dependabot-checks.yml` prints the step name
- [x] `env DEVELOPMENT_TEAM= make build-mac` passes locally (the leg CI runs; `make build-mac` already sets `CODE_SIGNING_ALLOWED=NO`)
- [x] `bash scripts/test.sh` prints `gate: ok` (the repo gate still passes with the new files present; nothing in the gate reads `.github/`)

#### Manual
- [ ] Commit and push the branch; open its PR. The branch PR is a **human** PR, so confirm GitHub shows the `Dependabot checks` workflow as a single `Skipped` entry and that **no** step executed.
- [ ] Merge to `main` (rebase merge). Dependabot-triggered `pull_request` runs use the workflow definition from the base repo, so this step is mandatory before any dependabot PR can exercise it (design Open Risk 2).
- [ ] On `main`, open **Insights → Dependency graph → Dependabot → Check for updates** to force a github-actions PR immediately (otherwise wait for the weekly run).
- [ ] On the resulting dependabot PR, confirm exactly one check named `Dependabot checks / gate` runs and turns green, with the steps `Select Xcode 27`, `Guard Xcode 27 and macOS 27 SDK` and `Build (macOS, unsigned)` all executed (not skipped). Inspect the guard step log: `xcodebuild -version` reports 27.x and `macOS SDK version: 27.*`.
- [ ] **Kill criterion**: if no Xcode 27 exists on `macos-26`, the workflow fails in `Select Xcode 27` with the available bundle list. Stop; re-run `design`. Do not proceed to Phase 2.

---

## Phase 2: Simulator + watch compile legs

Adds `make build` (iOS generic simulator destination) and `make watch-build`,
so a dependabot PR verifies iOS and watchOS still compile. This also resolves
design Open Risk 3 (a `generic/` destination for the `build` action on a scheme
carrying testables) while nothing downstream depends on the answer.

### Changes

#### 1. `.github/workflows/dependabot-checks.yml` (modify)

Two steps, inserted to preserve `scripts/test.sh` order
(`make build` first; `make watch-build` after `make build-mac`). The `SIM` env
value already exists from Phase 1.

Insert before `Build (macOS, unsigned)`:

```yaml
      - name: Build (iOS Simulator)
        run: make build
```

Insert after `Build (macOS, unsigned)`:

```yaml
      - name: Build (watchOS Simulator)
        run: make watch-build
```

**Contract / fallback:** if xcodebuild rejects `generic/platform=iOS Simulator`
for the `build` action, the only change is the `SIM` job-env value (to a
`name=`-pinned device verified present on the image) — no step shape changes.
Never commit a bare `name=` destination without checking it exists on the image;
prefer a generic destination.

### Verification

#### Automated
- [x] `actionlint .github/workflows/dependabot-checks.yml` exits 0
- [x] `env SIM='generic/platform=iOS Simulator' make build` passes locally on a clean `DerivedData` (delete `DerivedData/` first)
- [x] `make watch-build` passes locally on a clean `DerivedData`
- [x] Step order assertion: `grep -nE 'name: Build \((iOS Simulator|macOS, unsigned|watchOS Simulator)\)' .github/workflows/dependabot-checks.yml` lists iOS, macOS, watchOS in that line order

#### Manual
- [ ] On the dependabot PR, the check is green and both new steps show as executed. Open the `Build (iOS Simulator)` step log and confirm xcodebuild accepted `-destination generic/platform=iOS Simulator`.
- [ ] If Open Risk 3 materialises (generic destination rejected), apply the `SIM` fallback and re-run locally before pushing. Do not leave a bare `name=` destination unreviewed.

---

## Phase 3: Test suites leg

Adds the real verification capability: the macOS-hosted unit bundle and the
fully-stubbed shell suite. This is the first phase where a broken commit fails
the check on a **test**, not a compile.

### Changes

#### 1. `.github/workflows/dependabot-checks.yml` (modify)

Two steps. `make test-unit` goes after `Build (iOS Simulator)` and before
`Build (macOS, unsigned)` (mirrors the gate's `make test` position after
`make build`). `bash scripts/tests/run.sh` goes after
`Build (watchOS Simulator)`.

Insert after `Build (iOS Simulator)`:

```yaml
      - name: Unit tests (macOS host)
        run: make test-unit
```

Insert after `Build (watchOS Simulator)`:

```yaml
      - name: Shell suite
        run: bash scripts/tests/run.sh
```

**Contract:** unit scoping stays `-only-testing:CheckStitchTests` inside
`Makefile:70`; the workflow passes **no** test selector and never calls
`make test` (which would drag in `make test-ui` / a real simulator). Any future
test-suite change is invisible to the YAML. `scripts/tests/run.sh` is CI-safe by
construction (it stubs `make xcrun defaults open osascript` on a temp `PATH`);
the runner needs no isolation changes.

### Verification

#### Automated
- [x] `actionlint .github/workflows/dependabot-checks.yml` exits 0
- [x] `make test-unit` passes locally
- [x] `bash scripts/tests/run.sh` passes locally and exits 0
- [x] No test selector in YAML: `! grep -E 'only-testing|test-ui|make test($|[^-])' .github/workflows/dependabot-checks.yml` (expects no match; `make test-unit` is allowed)

#### Manual
- [ ] On the dependabot PR, both new steps execute and the check is green.
- [ ] **Not-a-no-op proof (design Open Risk 2):** push a deliberately broken commit onto the dependabot branch and confirm the check goes red on `Unit tests (macOS host)` (or `Shell suite`), not on a compile step:
  ```bash
  git fetch origin
  dep_branch=$(git ls-remote --heads origin 'dependabot/*' | head -1 | awk '{print $2}' | sed 's#refs/heads/##')
  git checkout -b verify-red "origin/$dep_branch"
  # break a test, e.g. add a failing #expect to CheckStitchTests/SmokeTests.swift
  git commit -am "test: deliberately break the unit suite"
  git push origin HEAD:"$dep_branch"
  gh pr checks   # wait for red on Unit tests (macOS host)
  ```
  Restore afterwards with `git push --force origin <original-sha>:"$dep_branch"` (the dependabot branch is in this repo, not a fork). Dependabot may also force-push its own update, which restores it.

---

## Phase 4: Lint leg (shellcheck, strict)

Makes gate step 7 real shellcheck instead of the gate's silent `bash -n`
fallback (`scripts/test.sh:113-119`), so `scripts/*.sh` regressions fail CI.

### Changes

#### 1. `.github/workflows/dependabot-checks.yml` (modify)

Two steps, appended after `Shell suite` (lint runs only after the shell suite,
matching gate order). `shellcheck` is **not** preinstalled on `macos-26`, so it
must be installed; no `bash -n` fallback is tolerated in CI.

```yaml
      - name: Install shellcheck
        run: brew install shellcheck

      - name: Lint (shellcheck)
        run: shellcheck scripts/*.sh scripts/tests/*.sh
```

(The globs are expanded by the runner's bash; the whole value is a single YAML
string, so no YAML quoting subtleties.)

**Contract:** the lint step must not degrade — if `shellcheck` is unavailable
after the install step, the run fails (nothing in the workflow substitutes
`bash -n`).

### Verification

#### Automated
- [x] `actionlint .github/workflows/dependabot-checks.yml` exits 0
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` passes locally
- [x] `! grep -F 'bash -n' .github/workflows/dependabot-checks.yml` (no fallback in CI)

#### Manual
- [ ] On the dependabot PR the `Lint (shellcheck)` step log shows shellcheck output (and is **not** the `bash -n` fallback); confirm by searching the step log for a shellcheck run, not merely trusting the step name (design Open Risk 5).
- [ ] If `brew install shellcheck` proves flaky/slow, do not silently drop the step: surface it. The accepted degradation (per design Open Risk 5) is reverting to the gate's `bash -n` fallback, which is a design decision, not an inline tweak.

---

## Phase 5: Hardening

Blast-radius controls and final parity evidence. No new leg.

### Changes

#### 1. `.github/workflows/dependabot-checks.yml` (modify)

Add three workflow/job keys. These are final; later maintenance is version
bumps only (now tracked by the Phase 1 `github-actions` dependabot ecosystem).

Add after the `on:` block (workflow level):

```yaml
permissions:
  contents: read

concurrency:
  group: dependabot-checks-${{ github.ref }}
  cancel-in-progress: true
```

Add under `jobs.gate` (job level):

```yaml
    timeout-minutes: 45
```

**Contract:** `permissions: contents: read`, the concurrency group, and the
45-minute timeout are the final shape. The deliberately floating `@v4` / `@v1`
action tags stay floating so the new `github-actions` dependabot ecosystem has
updates to open.

### Verification

#### Automated
- [x] `actionlint .github/workflows/dependabot-checks.yml` exits 0
- [x] `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/dependabot-checks.yml'))"` exits 0
- [x] `grep -F 'permissions:' .github/workflows/dependabot-checks.yml` and `grep -F 'timeout-minutes: 45' .github/workflows/dependabot-checks.yml` both match
- [x] Full local six-step reproduction on clean `DerivedData` matches CI order:
  ```bash
  rm -rf DerivedData
  env DEVELOPMENT_TEAM= SIM='generic/platform=iOS Simulator' make build
  make test-unit
  env DEVELOPMENT_TEAM= make build-mac
  make watch-build
  bash scripts/tests/run.sh
  shellcheck scripts/*.sh scripts/tests/*.sh
  ```
  All exit 0.
- [x] `git status --short` shows only `.github/dependabot.yml` and `.github/workflows/dependabot-checks.yml` as added/changed (plus the committed `.pi/` artifact directory); confirm no change to `Makefile`, `scripts/`, `CheckStitch.xcodeproj/xcshareddata/`, or `project.pbxproj`: `git diff --name-only` contains no such paths.
- [x] `bash scripts/test.sh` prints `gate: ok` (the repo gate, run before committing).

#### Manual
- [ ] On the dependabot PR, the check is green, total runtime is comfortably under 45 minutes (read the run duration from the check page), and all seven legs execute in gate order: iOS build → unit tests → macOS build → watch build → shell suite → shellcheck.
- [ ] Rebase/close the PR while a run is in flight (or push twice quickly) and confirm GitHub shows the earlier run cancelled rather than queued (concurrency `cancel-in-progress`).
- [ ] Confirm a human PR still shows only the `Skipped` row and never executes a step.

---

## Appendix A: Complete final workflow (end state after Phase 5)

Reference for implementers; Phases 1–5 build this incrementally.

```yaml
name: Dependabot checks

on:
  pull_request:

permissions:
  contents: read

concurrency:
  group: dependabot-checks-${{ github.ref }}
  cancel-in-progress: true

jobs:
  gate:
    if: github.event.pull_request.user.login == 'dependabot[bot]'
    runs-on: macos-26
    timeout-minutes: 45
    env:
      DEVELOPMENT_TEAM: ""
      SIM: generic/platform=iOS Simulator
    steps:
      - uses: actions/checkout@v4

      - name: Select Xcode 27
        run: |
          set -euo pipefail
          for app in /Applications/Xcode*.app; do
            if [[ "$("$app/Contents/Developer/usr/bin/xcodebuild" -version 2>/dev/null | head -1)" == "Xcode 27."* ]]; then
              echo "Selecting $app"
              sudo xcode-select -s "$app/Contents/Developer"
              exit 0
            fi
          done
          echo "No Xcode 27.x found. Available Xcode bundles:" >&2
          ls -d /Applications/Xcode*.app >&2 || true
          exit 1

      - name: Guard Xcode 27 and macOS 27 SDK
        run: |
          set -euo pipefail
          xcodebuild -version
          xcodebuild -version | head -1 | grep -q '^Xcode 27\.' \
            || { echo "expected Xcode 27.x" >&2; exit 1; }
          sdk_version="$(xcrun --sdk macosx --show-sdk-version)"
          echo "macOS SDK version: $sdk_version"
          [[ "$sdk_version" == 27.* ]] \
            || { echo "expected macOS 27 SDK, got: $sdk_version" >&2; exit 1; }

      - name: Build (iOS Simulator)
        run: make build

      - name: Unit tests (macOS host)
        run: make test-unit

      - name: Build (macOS, unsigned)
        run: make build-mac

      - name: Build (watchOS Simulator)
        run: make watch-build

      - name: Shell suite
        run: bash scripts/tests/run.sh

      - name: Install shellcheck
        run: brew install shellcheck

      - name: Lint (shellcheck)
        run: shellcheck scripts/*.sh scripts/tests/*.sh
```

## Appendix B: Out of scope (do not implement)

No UI tests / `make test-ui`; no gate edits (`scripts/test.sh`,
`scripts/tests/run.sh`, `Makefile`, schemes); no host-simulator machinery
(`.simulator_id`, `resolve-sim-udid.sh`, lock, `osascript`, `simctl`); no signed
or device legs (`build-mac-signed`, `run-devices.sh`, `run-watch.sh`,
`devicectl`); no branch protection / required checks; no caching, artifact
upload, matrix, secret scanning, `push`/`schedule`/`workflow_dispatch`
triggers, Xcode Cloud changes, or TestFlight automation. Do not create child
tickets — all work is on VAR-1029.