# Implementation Summary

All five phases of the VAR-1010 plan implemented, each verified and committed
by a separate worker subagent, then pushed to
`origin/alanvardy-var-1010-resolve-all-warnings` (draft PR #61).

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `e97d503` | Walking skeleton — macOS leg enforced end to end |
| 2     | `4c3b800` | iOS simulator build leg enforced |
| 3     | `e4533fb` | Unit-test leg enforced |
| 4     | `88afbb4` | UI-test and watch legs enforced |
| 5     | `bfac393` | Hardening — full-gate confidence and docs |

## Automated Checks

- [x] `bash scripts/tests/run.sh` → `tests: 24 passed, 0 failed` (all phases, incl. `warnings_as_errors_reaches_compiling_legs` and `warnings_as_errors_guard_detects_a_stripped_flag`)
- [x] `make build-mac` exits 0 with no compiler `warning:` lines
- [x] `make build` exits 0 with no compiler `warning:` lines
- [x] `make test-unit` exits 0, prints `** TEST SUCCEEDED **`, no compiler `warning:` lines
- [x] `make test-ui` exits 0 (`** TEST EXECUTE SUCCEEDED **`, UI smoke 0 failures)
- [x] `make watch-build` exits 0 with no compiler `warning:` lines
- [x] `./scripts/test.sh` prints `gate: ok`
- [x] Fresh-cache confidence run `rm -rf DerivedData && ./scripts/test.sh` prints `gate: ok`
- [x] `shellcheck scripts/*.sh scripts/tests/*.sh` clean
- [x] `grep -n 'WARNINGS_AS_ERRORS' Makefile` — declaration + one line per enforced leg recipe; `build-mac-signed` untouched
- [x] `grep -n 'try #require' CheckStitchTests/WatchChecklistStoreTests.swift` → only line 230 (genuine `#require` intact)
- [x] Line 1476's `created` still referenced (`created.id`); only line 1456 unwrapped
- [x] CI inherited enforcement by construction (`.github/workflows/dependabot-checks.yml` drives the legs via make recipes; no edit needed)

## Manual Verification Items (from the plan)

- [ ] **Phase 1** — Inject a warning and confirm `make build-mac` fails, then revert:
  `printf '\nfunc __warnProbe() {\n    let unusedProbe = 1\n}\n' >> CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift`
  → `make build-mac` exits non-zero with `error: initialization of immutable value 'unusedProbe' was never used`
  → `git checkout -- CheckStitchCore/Sources/CheckStitchCore/ChecklistItemPriority.swift`
- [ ] **Phase 2** — Re-run the deliberate-warning probe; confirm both `make build` and `make build-mac` fail on it, then revert
- [ ] **Phase 3** — Confirm the four `#require` sites and line 230 (automated-diff confirms, but user sign-off on the manual probes):
  `grep -n 'try #require' CheckStitchTests/WatchChecklistStoreTests.swift` shows only line 230; and
  `sed -n '1470,1482p' CheckStitchTests/ChecklistStoreTests.swift` shows line 1476's `created` still referenced
- [ ] **Phase 4** — Deliberate-warning probe: confirm `make watch-build` and `make test-ui` fail on it, then revert
- [ ] **Phase 5** — For each of `make build-mac`, `make build`, `make test-unit`, `make watch-build`, inject the `__warnProbe` warning, confirm that leg fails, then revert (one representative leg is enough if time-boxed; CI on a fresh checkout is the backstop)
- [ ] **Phase 5** — Confirm the AppIntents metadata note does **not** fail any leg (it is a build-phase message, not a diagnostic)

## Notes / Observations from implementation

- **Phase 1 non-fast-forward push.** The parent rebased the branch onto
  `origin/main` before phase work began, rewriting the base commit
  (`6423802` → `36a45be`). The Phase 1 push was therefore rejected as
  non-fast-forward. Verified via `git merge-base --is-ancestor` that the
  remote tip was the pre-rebase start commit (no foreign changes from another
  contributor) and published the rebased branch with a `--force-with-lease`
  push. Phases 2–5 fast-forwarded cleanly.
- **`plan.md` quoted sad-path sed vs shellcheck.** The plan's single-quoted
  `sed 's/ \$(WARNINGS_AS_ERRORS)//'` trips shellcheck SC2016 (which is part
  of the gate), failing the pre-existing gate tests under `set -e`. Phase 1
  used the behavior-identical double-quoted form
  (`sed "s/ \$(WARNINGS_AS_ERRORS)//"`), which strips the exact literal and
  keeps shellcheck clean. This satisfies Phase 5's `shellcheck clean`
  requirement.
- **`#require` unwrap drops `try`.** My Phase 3 task paraphrase kept
  `try store.run(checklist)`; the worker correctly followed the plan's snippet
  `let runID = store.run(checklist)`. Dropping `try` is required:
  `WatchChecklistStore.run()` returns a non-optional `UUID` and does not
  throw, so `try` over it is a compiler error. Exactly 4 sites changed; the
  genuine `#require` at line 230 and all other `#require`s untouched.
- **SPM propagation confirmed in practice.** The flags-on macOS build failing
  a reverted probe (per plan) plus the clean fresh-cache gate confirm the
  `WARNINGS_AS_ERRORS` override reaches `CheckStitchCore` SPM package targets.
- **Known limitation (from plan).** Incremental `DerivedData` can hide warnings
  (legs share the cache); CI on a fresh checkout is the authoritative backstop,
  which the Phase 5 `rm -rf DerivedData` confidence run exercised.