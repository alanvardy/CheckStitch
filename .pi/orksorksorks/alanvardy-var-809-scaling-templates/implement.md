# Implementation Summary

Added a per-checklist `multiple: Int` (default `1`, range `1...99`) that scales every
`((n))` marker in an item's title/description to `n × multiple` at reminder-creation
time (stored text never rewritten), with a Scaling `Stepper` on the detail screen,
scaled read-only surfaces (iOS/macOS rows, Watch detail) plus a `×N` row badge when
`multiple > 1`, and an optional `RunChecklistIntent` override validated before any
side effect.

## Commits

| Phase | Commit | Description |
|-------|--------|-------------|
| 1     | `14ad002` | Walking skeleton — set a multiple and run a checklist with a scaled marker |
| 2     | `e5c3628` | Read-only surfaces render scaled text, with a ×N row badge |
| 3     | `1b5fb6d` | Persistence integrity — multiple survives duplicate, export/import, merge |
| 4     | `2b0241d` | Intent override — one-run multiple with side-effect-free validation |
| 5     | `29cb3a6` | Hardening — edge cases, i18n completeness, full gate |

All pushed fast-forward to `origin/alanvardy-var-809-scaling-templates`. Helper readonly
placeholder `DELETEME` untouched; no other branches touched. No child tickets.

## Automated Checks

- [x] `make test-unit` passes — 556 tests / 66 suites green (verified after each phase)
- [x] `make build` passes — simulator, warnings-as-errors clean (Phase 1)
- [x] `make watch-build` passes (Phase 2, Phase 5)
- [x] `scripts/l10n-check.sh` passes — 4 catalogs, 161 keys, 6 languages (`Scaling`, `×%lld`, Core `Multiple must be between 1 and 99.`)
- [x] `./scripts/test.sh` prints `gate: ok` (Phase 5 full gate)

### Worker-flagged adaptations (all plan-internal, none structural)
- **Codec test API**: plan's `ChecklistCodec.encode([Checklist])` doesn't exist; tests use the real `encode(ChecklistEnvelope)`.
- **Resolver `((3)))`** test arg: the plan's code conflicted with its own pass-through expectation; resolved by treating a closing `))` followed by a third `)` as a non-marker so `((3)))` passes through byte-for-byte.
- **`×%lld` + GenerateStringSymbols (supervisor-approved, Option A)**: the CheckStitch app target sets `STRING_CATALOG_GENERATE_SYMBOLS = YES`, and Xcode's GenerateStringSymbols hard-fails on the `×`-leading key (`×` isn't a valid Swift identifier char). Scoped `STRING_CATALOG_GENERATE_SYMBOLS = NO` to the **two CheckStitch app-target configs only** (Debug + Release); the Watch/project-level YES settings left untouched. App source uses only `String(localized: table: bundle:)` with zero references to generated string symbols, so the change is safe. Badge resolves `×%lld` at runtime via `Bundle.main.localizedString(forKey:table:)` + `String(format:)`.

## Manual Verification Items (from the plan)

Phase 1 —
- [ ] `make run`; open a checklist, see the Scaling stepper; increment to `2`
- [ ] Add an item titled `Milk ((3))` with description `((4)) boxes`; run it; the created reminders read `1: Milk 6` / notes `8 boxes`
- [ ] Confirm the stored item text still reads `Milk ((3))` after the run

Phase 2 —
- [ ] `make run`: with Scaling `3`, rows preview `×3` and show resolved text; set Scaling `1`, the badge disappears and raw `((n))` shows
- [ ] `ItemEditView` still shows the raw `((n))` text
- [ ] `bash scripts/run-watch.sh`: the Watch detail shows the scaled title/description and no badge (installed bundle)

Phase 3 —
- [ ] `make run`: duplicate a checklist set to Scaling `4`; the copy shows `4`
- [ ] Export a scaled checklist and import it; the imported copy keeps the factor

Phase 4 —
- [ ] In Shortcuts, run "Run Checklist" with no Multiple → stored factor applies
- [ ] Run with Multiple `4` → this run scales by 4; re-run without it → stored factor returns
- [ ] Run with Multiple `0` → `Multiple must be between 1 and 99.` and no reminders created

Phase 5 —
- [ ] Installed-bundle Watch render check per `AGENTS.md` (scaled title/description, no badge)
- [ ] Confirm no `ChecklistCodec.currentVersion` reference changed and no test references a new schema version (`currentVersion` stayed `5`; no migration, no codegen)