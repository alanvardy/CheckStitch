# Done

- **Branch / head SHA**: `alanvardy-var-1029-enable-checks-for-dependabot-prs` @
  `b466760d3af54b2e6d6b9be6fa67bca6fc046dec` (pushed; remote in sync).
- **Mechanical checks**:
  - `./scripts/test.sh` → `gate: ok`, exit 0 (237 unit tests / 33 suites, 17
    shell-suite tests, shellcheck clean) — run on the branch before fixes.
  - `actionlint .github/workflows/dependabot-checks.yml` → exit 0 (after the fix
    below; before it, the new `xcode-27` label tripped actionlint's stale label
    list).
  - YAML parse of `.github/dependabot.yml`, `.github/workflows/dependabot-checks.yml`,
    `.github/actionlint.yaml` → ok.
  - No warnings flagged.
- **Review outcome**:
  - **Blocker (fixed):** the workflow ran on `runs-on: macos-26`, which ships
    only Xcode 26.0.1–26.6; `MACOSX_DEPLOYMENT_TARGET = 27.0` requires the macOS
    27 SDK, so the `Select Xcode 27` step exited 1 on every run and the workflow
    could never go green. Fixed to `runs-on: xcode-27`, the label GitHub
    documents for the Xcode 27 preview image
    ([actions/runner-images#14404](https://github.com/actions/runner-images/issues/14404)),
    verified against the live `xcode-27-arm64` / `macos-26-arm64` image manifests.
    This was the design's Open Risk 1 kill criterion firing late (it is only
    observable on a real run).
  - **Fixes worth doing now (fixed):** runner label; missing trailing newline in
    `.github/dependabot.yml`.
  - **Optional improvements (applied, per user choice [2]):** comment documenting
    that the job-level `if` produces a `Skipped` row on human PRs and must not be
    added to required branch-protection checks; comment explaining why
    `brew install shellcheck` precedes the lint step.
  - **New file (required by the fix):** `.github/actionlint.yaml` declaring the
    `xcode-27` label, because actionlint's built-in label list predates the
    preview image. This is a third committed file beyond the design's "two files,
    nothing else", added solely to keep the documented actionlint check green.
  - **Declined:** SHA-pinning `actions/checkout` (the floating tag is intentional
    so the `github-actions` dependabot ecosystem has something to bump); dropping
    `DEVELOPMENT_TEAM: ""`.
  - **Reviewer note:** one reviewer finding cited `scripts/test.sh:36` as
    "Xcode 26.6 evidence"; that line is a historical comment about a phase-1
    spike. The actual toolchain is Xcode 27.0 / macOS SDK 27.0.
- **Remaining manual items** (post-merge only — dependabot `pull_request` runs
  use the workflow from the base repo):
  - [ ] Merge this PR to `main` (rebase merge); the workflow must be on `main`
        before any dependabot PR can exercise it.
  - [ ] Open a real dependabot PR (Insights → Dependency graph → Dependabot →
        Check for updates) and confirm one executed green `Dependabot checks / gate`
        check, with `Select Xcode 27`, `Guard Xcode 27 and macOS 27 SDK` and
        `Build (macOS, unsigned)` executed — not skipped. Confirm the guard log
        shows Xcode 27.x and `macOS SDK version: 27.*`.
  - [ ] Confirm a human PR shows only the `Skipped` row and never executes a step.
  - [ ] Not-a-no-op proof: push a deliberately broken commit onto the dependabot
        branch and confirm the check goes red on a test step, then restore.
  - [ ] Confirm `Build (iOS Simulator)` accepted `generic/platform=iOS Simulator`
        on the runner (design Open Risk 3).
  - [ ] `xcode-27` is a **preview** label — expect possible queueing/instability
        until GA; if it proves unusable, the macOS leg needs a design re-scope
        rather than an inline tweak.