# Done

- **Branch / reviewed code head SHA**: `alanvardy-var-1127-scaling-prompt` /
  `1a466ed` (pushed;
  `origin == HEAD`). Parent commit `b60b997` recorded the pending `DELETEME`
  deletion and the step artifacts. No rebase conflicts were pending (no
  `REBASE_HEAD`, clean tree at start; forced push not needed for the final
  commit — both pushes were fast-forward).

- **Mechanical checks**:
  - `./scripts/test.sh` (the repo gate: sim build → sim test → `build-mac` →
    `watch-build` → `scripts/tests/run.sh` → shellcheck) → `gate: ok`
    (`tests: 26 passed, 0 failed`, `GATE_EXIT=0`), warnings-as-errors on.
  - `scripts/l10n-check.sh` → `l10n-check: ok (4 catalogs, 186 keys, 6 languages)`.
  - `make test-unit` after the review fixes → `642 tests in 69 suites passed`.
  - Full gate re-run on the final head → `gate: ok`.

- **Review outcome** (one bounded `reviewer`, fresh context; findings
  cross-checked against source and the design/plan):
  - **Blockers**: none.
  - **Fixes applied** (`1a466ed`):
    1. `ChecklistRunViewModelTests.fixedModeRunsImmediatelyWithoutPrompting` now
       captures and awaits the spawned run task and asserts
       `spy.createdTitles == ["milk 6"]` (was discarding the task, leaving an
       orphan and asserting nothing about creation).
    2. `ChecklistReminders.create` now clamps `multipleOverride` through
       `Checklist.clampedMultiple`, restoring the single clamp source as
       defense-in-depth.
    3. Added the missing trailing newlines in `PromptScalingSheet.swift`,
       `PromptScalingSheetTests.swift`, `ScalingTests.swift`,
       `ChecklistRunViewModelTests.swift`.
  - **Deferred / declined**: the app detail rows resolve Prompt previews through
    `scaling.number` while the watch uses `displayNumber`. This is the plan's
    explicit Phase-3 decision (`plan.md:944`, design decision 10: the badge is
    suppressed but row text keeps `multiple` behaviour), so it was left as-is.
    Flagged to the user as a possible cross-surface UX inconsistency for a
    later decision.

- **Remaining manual items**: the plan's device/Siri verification items in
  `implement.md` are still unconfirmed, notably:
  - Prompt-mode AppIntents `requestValue` headless/cancelled behaviour (does it
    throw → friendly fallback dialog, or return a default → `invalidMultiple`?).
  - `make run` Prompt picker, sheet validation, persisted mode after relaunch.
  - Shortcuts/Siri prompt, widget-button fallback, watch neutral preview, and
    the on-device mode-toggle round trip.
