# Task

Make every pull request opened by Dependabot in this repo tag/request a
review from `alanvardy`, so the owner is notified to review each automated
dependency bump.

Recon notes (verify before acting):

- `.github/dependabot.yml` currently configures `reviewers: ["alanvardy"]`
  for the `github-actions` updates entry only. Confirm whether that
  mechanism actually results in a review request on opened dependabot PRs
  (dependabot.yml `reviewers` applies per ecosystem and at PR creation
  time only), and whether it covers all dependabot PRs in practice. Close
  whatever gap remains — e.g. extend the existing config and/or add an
  explicit request-review step for `dependabot[bot]` PRs.
- `.github/workflows/dependabot-checks.yml` is the existing dependabot-only
  workflow (`if: github.event.pull_request.user.login == 'dependabot[bot]'`,
  runner `xcode-27`) — any workflow-based approach should follow it, and
  stay gated to the dependabot actor (never tag reviewers on human PRs).
- Workflows are linted with actionlint (`.github/actionlint.yaml` at repo
  root configures it) — validate any workflow edits against it.
- The repo gate is `bash scripts/test.sh`; `scripts/tests/run.sh` stubs
  external CLIs for shell-suite coverage of `scripts/*.sh`.

## Why SMALL

Single-module, ≤2-file change confined to `.github/` following existing
dependabot/CI patterns; approach known (the `reviewers` key is already the
established pattern in this repo), no schema, no new subsystem, no design
trade-off, tests few and local.

## Key files

- `.github/dependabot.yml` — existing updates config; `github-actions`
  entry already sets `reviewers: ["alanvardy"]`
- `.github/workflows/dependabot-checks.yml` — existing dependabot-only
  workflow to extend or mirror if a request-review step is needed
- `.github/actionlint.yaml` — actionlint config; run actionlint on any
  workflow edit