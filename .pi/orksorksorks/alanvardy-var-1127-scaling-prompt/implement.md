# Implementation Summary

Plan: `.pi/orksorksorks/alanvardy-var-1127-scaling-prompt/plan.md`
Branch: `alanvardy-var-1127-scaling-prompt`

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 0     | `fa47242` | Scaling type end to end, `.fixed` unchanged |
| 1     | `ffa4ced` | In-app Prompt scaling, end to end |
| 2     | `04f0c01` | App-Intent prompt (Siri / Shortcuts) |
| 3     | `fc1862c` | Hardening, display polish, rollout |

Each phase was implemented, verified and committed by a single worker, one phase
at a time. All four commits were pushed to
`origin/alanvardy-var-1127-scaling-prompt`.

## Automated Checks

- [x] Phase 0 — `make test-unit` passed; `make build-mac` passed; `bash scripts/l10n-check.sh` printed `l10n-check: ok`
- [x] Phase 1 — `make test-unit` passed; `make build` passed
- [x] Phase 2 — `make test-unit` passed; `make build` passed; `make watch-build` passed; `bash scripts/l10n-check.sh` printed `l10n-check: ok`
- [x] Phase 3 — `bash scripts/l10n-check.sh` printed `l10n-check: ok`; `make test-unit` passed; `make build` passed
- [x] Full gate — `./scripts/test.sh` printed `gate: ok` (sim build → sim test → `build-mac` → `watch-build` → `scripts/tests/run.sh` → shellcheck; `tests: 26 passed, 0 failed`)

## Manual Verification Items (from the plan)

These are NOT confirmed — the user verifies them.

### Phase 0
- [ ] `git diff` shows `currentVersion` untouched and no `ChecklistCodec.classify` change
- [ ] A hand-saved payload containing `"multiple": 5` and no `scalingMode` still loads in the app as Scaling 5 (temporarily with `make run`; or trust the codec fixture)

### Phase 1
- [ ] `make run`: open a checklist → Scaling shows a Fixed/Prompt segmented picker; pick Prompt → the number field disappears; pick Fixed → the previous number returns
- [ ] With Prompt selected and items containing `((2))`, tap the run button → a sheet appears, field defaults to the last fixed number, Confirm is disabled for empty/`0`/`100` and enabled for `3`
- [ ] Confirm with `3` → reminders are created with markers × 3; return to the detail view and confirm the picker still says Prompt and the remembered number is unchanged
- [ ] Cancel → no reminders created, no error alert
- [ ] Kill and relaunch the app → the checklist is still Prompt (mode persisted)

### Phase 2
- [ ] In Shortcuts, run a Prompt checklist with no `Multiple` → Siri/Shortcuts asks for a number; the created reminders use it
- [ ] In Shortcuts, pass `Multiple: 2` on a Prompt checklist → no prompt, markers × 2
- [ ] Run a Prompt checklist from a widget button → record the outcome in the PR description (expected: the designed fallback, no reminders, since widgets are headless)
- [ ] Run a Fixed checklist from Siri → behaves exactly as before

### Phase 3
- [ ] `make run`: a Prompt checklist shows no `×N` badge; a Fixed checklist with 3 shows `×3`
- [ ] `bash scripts/run-devices.sh` (or `make run` on the watch leg): a Prompt checklist's watch rows show un-multiplied marker text and no badge
- [ ] Toggle to Prompt then back to Fixed on the device → the remembered number survives

## Observations / Deviations

- **`plan.md` staged by workers (process deviation).** `plan.md` was untracked at
  the start of this run; the Phase 0 worker committed it together with its phase
  files, so it is now tracked. Subsequent phase commits carry their own `plan.md`
  checkbox delta to keep progress recorded in git. No other artifact file from
  `.pi/orksorksorks/<branch>/` was staged, and the `DELETEME` deletion remains
  uncommitted.
- **Phase 1 `ContentView` helper extraction.** The inline `.sheet(item:)` binding
  tripped a SwiftUI type-check timeout; the binding and sheet content were
  extracted into `promptingScalingBinding` / `promptingScalingSheet(for:)`.
  Behaviour is identical to the plan.
- **Phase 2 test seam visibility.** `TestFixtures.swift` needed
  `@testable import CheckStitchCore` (rather than plain `import`) so the test
  target can see the internal `ScalingPrompting` protocol. The plan's test init
  was made non-`public` as specified.
- **Phase 2 `requestValue` spike.** The production `AppIntentScalingPrompter`
  compiles against the SDK and the intent path is covered by the injected fake
  prompter; the manual Shortcuts/widget behaviour is unverified here and is listed
  above. The designed headless fallback (dialog, no reminders) is exercised by
  tests rather than by hand.
- No unrelated refactors or cleanups were made; the `CheckStitchWidget` target is
  untouched (design decision, per the plan).
