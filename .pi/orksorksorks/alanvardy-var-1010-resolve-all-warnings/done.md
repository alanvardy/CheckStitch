# Done

- **Branch / head SHA**: `alanvardy-var-1010-resolve-all-warnings` @ `2e4ad92`
  (pushed to `origin` with `--force-with-lease`)
- **Mechanical checks**: `./scripts/test.sh` → `gate: ok`. All five compiling
  legs pass with warnings-as-errors on (`make build`, `make build-mac`,
  `make test-unit`, `make test-ui`, `make watch-build`); `bash scripts/tests/run.sh`
  → `tests: 24 passed, 0 failed`; `shellcheck scripts/*.sh scripts/tests/*.sh`
  clean. No warnings flagged.
- **Review outcome**: One fresh-context reviewer over `git diff main...HEAD`,
  plus own scan. **No blockers.** Four source fixes verified semantically
  equivalent (`first(where:)` vs `first { }`; `_ = await refresh()`; four
  `#require` unwraps where `WatchChecklistStore.run(_:) -> UUID` is
  non-optional/non-throwing at `ChecklistSync.swift:296`; unused-binding
  discards). Makefile variable reaches all five enforced legs and leaves
  `build-mac-signed`/device helpers untouched. Harness happy + sad paths pass
  for the right reasons. No new force unwraps. Docs match behaviour.
  **No fixes worth doing now, so no edits made** (not autofix mode).
  Optional nits noted, not applied: (1) `scripts/tests/run.sh:398` awk assertion
  is line-count strict; (2) sad-path `sed` at `:415` strips all recipes rather
  than just `build-mac`; (3) redundant second `export SIM` at `:404`.
- **Remaining manual items**: Phase manual probes from `plan.md` (deliberate
  `__warnProbe` injection per leg, confirming each fails then reverting; and
  confirming the AppIntents metadata note is not a diagnostic) remain
  user-facing sign-off items — CI on a fresh checkout is the backstop.