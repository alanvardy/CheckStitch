# Structure Outline

## Approach

Ship two committed files — `.github/dependabot.yml` (so dependabot PRs exist)
and `.github/workflows/dependabot-checks.yml` (a single job, `pull_request` +
dependabot-author `if`, running the portable gate legs in `scripts/test.sh`
order, provisioning-free). The "stack" here is *repo config → GitHub Actions
runner → gate leg*; there is no app code, schema, or UI change. Slicing is by
**which real leg executes on a dependabot PR**: each phase adds gate legs in
dependency → risk → value order, and each phase is independently demoable as a
check-run on a real dependabot PR.

**Genuinely horizontal, folded into Phase 1**: `.github/dependabot.yml` is
config-only and creates no observable behaviour by itself — it is the *source*
of dependabot PRs, so it lands with the walking skeleton. No other horizontal
work exists.

## Phase 1: Walking skeleton — a dependabot PR runs a real check

Committed dependabot config produces action-bump PRs; the workflow fires only on
those, selects Xcode 27, and executes the cheapest real portable leg
(`make build-mac`), which also exercises the exact risk that forces Xcode 27
(`MACOSX_DEPLOYMENT_TARGET = 27.0`). Green check proves trigger + guard +
toolchain + checkout + one real build are wired end to end.

**Files**: `.github/dependabot.yml` (new), `.github/workflows/dependabot-checks.yml` (new)
**Key changes**:
- `name: Dependabot checks`, `on: pull_request`, `jobs.gate.if: github.event.pull_request.user.login == 'dependabot[bot]'` — new
- `runs-on: macos-26`, job `env: { DEVELOPMENT_TEAM: "", SIM: "generic/platform=iOS Simulator" }` — new
- Xcode selection: `maxim-lobanov/setup-xcode@v1` (pin resolved on first run) + a **guard step** asserting `xcodebuild -version` reports 27.x and the macOS 27 SDK exists — new
- `make build-mac` step — new
- `dependabot.yml`: `version: 2`, `github-actions` ecosystem, `directory: "/"`, weekly Mon 08:00 `America/Vancouver`, reviewer `alanvardy`, `open-pull-requests-limit: 5`

**Contract**: check-run name `Dependabot checks / gate`; job id `gate`; the
trigger/guard shape and Xcode-selection mechanism that later phases inherit. No
later phase changes these.

**Tests**: none in-repo (declarative YAML); verification is live. Parse
`workflow.yml`/`dependabot.yml` as YAML locally; assert the guard expression
string.
**Verify**: `make build-mac` locally with `DEVELOPMENT_TEAM=` passes; a real
dependabot PR shows one executed green check; a human PR shows only a `Skipped`
row. **Xcode 27 availability on `macos-26` is the phase's kill criterion** — if
the guard fails, stop and re-run `design` (Open Risk 1), do not patch onward.

---

## Phase 2: Simulator + watch compile legs

Adds the two remaining compile-only legs so a dependabot PR verifies iOS and
watchOS still build. Resolves Open Risk 3 (`generic/platform=iOS Simulator`
accepted for the `build` action with a scheme carrying testables) while nothing
downstream depends on the answer.

**Files**: `.github/workflows/dependabot-checks.yml`
**Key changes**:
- Step `make build` — new (consumes `SIM: generic/platform=iOS Simulator`)
- Step `make watch-build` — new
- Step order follows `scripts/test.sh:35, :95` (`build` before `build-mac`/`watch-build`)

**Contract**: if `generic/platform=iOS Simulator` is rejected for `build`, the
fallback is a `name=`-pinned device verified present on the image; the `SIM`
env value is the only thing that changes — no step shape changes.

**Tests**: none in-repo; live verification.
**Verify**: `SIM='generic/platform=iOS Simulator' make build` and
`make watch-build` pass locally on clean `DerivedData`; the dependabot PR check
goes green with both steps executed (not skipped).

---

## Phase 3: Test suites leg

Adds the real verification capability: the macOS-hosted unit bundle and the
fully-stubbed shell suite run on a dependabot PR. This is the first phase where
a broken commit actually fails the check on a *test*, not a compile.

**Files**: `.github/workflows/dependabot-checks.yml`
**Key changes**:
- Step `make test-unit` — new (unsigned, macOS host; `-only-testing` stays Makefile-side)
- Step `bash scripts/tests/run.sh` — new (CI-safe: stubs `make/xcrun/defaults/open/osascript`)

**Contract**: unit scoping remains `Makefile:70`; the workflow passes no test
selector. Any future test-suite change is invisible to the YAML.

**Tests**: none new in-repo; the legs *are* the test suites.
**Verify**: `DEVELOPMENT_TEAM= make test-unit` and `bash scripts/tests/run.sh`
pass locally; a deliberately broken commit on a dependabot branch turns the
check red on the offending step (proves the check is not a no-op — Open Risk 2).

---

## Phase 4: Lint leg (shellcheck, strict)

Adds the gate's step 7 as real shellcheck rather than the silent `bash -n`
fallback (`scripts/test.sh:113-119`), so `scripts/*.sh` regressions fail CI.

**Files**: `.github/workflows/dependabot-checks.yml`
**Key changes**:
- Step `brew install shellcheck` — new (before lint)
- Step `shellcheck scripts/*.sh scripts/tests/*.sh` — new (globs quoted in YAML as a single command string)

**Contract**: lint runs only after `scripts/tests/run.sh` (gate order); shellcheck
absence is *not* tolerated (no `bash -n` fallback in CI).

**Tests**: none new.
**Verify**: `shellcheck scripts/*.sh scripts/tests/*.sh` passes locally; the
dependabot PR check runs step 7 with shellcheck present (assert via step log,
not step name alone — Open Risk 5).

---

## Phase 5: Hardening

Makes the workflow safe to leave unattended once it is firing on real PRs. No
new leg; only blast-radius controls and parity/evidence.

**Files**: `.github/workflows/dependabot-checks.yml`
**Key changes**:
- `permissions: contents: read` — new
- `concurrency: { group: dependabot-checks-${{ github.ref }}, cancel-in-progress: true }` — new
- `jobs.gate.timeout-minutes: 45` — new
- Optional `step`-order/name alignment audit against `scripts/test.sh` (no gate edit — design Decision 2)

**Contract**: workflow-level keys above are final; later maintenance is
version bumps only (which the new `github-actions` dependabot ecosystem now
tracks — Phase 1's `@vN` pins are deliberately floating).

**Tests**: none new.
**Verify**: local six-step reproduction with
`SIM='generic/platform=iOS Simulator' DEVELOPMENT_TEAM=` on clean `DerivedData`
matches CI step-for-step; concurrent dependabot rebases cancel instead of
queueing; total runtime stays under the timeout.

---

## Testing Checkpoints

- **After Phase 1**: `make build-mac` green locally **and** the Xcode-27 guard
  passes on `macos-26` — the kill criterion. If not, stop; `design` re-run.
- **After Phase 2**: the iOS generic-destination `make build` is accepted
  (Open Risk 3 resolved) before any test leg is added on top.
- **After Phase 3**: a deliberately broken dependabot-branch commit fails the
  check on a test step (not a compile step).
- **After Phase 4**: step 7 log shows shellcheck output, not `bash -n`.
- **After Phase 5**: hardening keys present; local reproduction matches CI
  order; no gate file (`scripts/test.sh`, Makefile, schemes) was modified.

**Wrong layer to avoid**: schema → API → UI-style decomposition does not apply;
this is a two-file declarative change. Do not stage "write the whole workflow"
as one phase, and do not add a `push`/`schedule` trigger or UI tests — both are
explicitly out of scope (design: "What We're NOT Doing").