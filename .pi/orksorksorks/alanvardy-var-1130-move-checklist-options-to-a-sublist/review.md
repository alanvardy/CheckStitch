# Review — VAR-1130 Move checklist options to a sublist

**Reviewed code head:** `fc56958` (Phase 1 `dd1105f`, Phase 2 `a6707f2`, artifact/DELETEME commit `fc56958`)
**Base:** `main` @ `138e5bc`
**Reviewer:** builtin `reviewer`, fresh context, bounded single pass.

## Mechanical checks (run by the orchestrator, not the reviewer)

| Check | Result |
|---|---|
| `./scripts/test.sh` (full gate: `make build` → simulator pre-boot → `make test` → `make build-mac` → `make watch-build` → `scripts/tests/run.sh` → `shellcheck`) | **`gate: ok`** — `BUILD SUCCEEDED`, 26 shell tests passed |
| `scripts/l10n-check.sh` | **ok** (4 catalogs, 194 keys, 6 languages) |
| Dangling-reference scan in `ChecklistDetailView.swift` for all moved symbols | no matches |
| `DELETEME` placeholder | removed in `fc56958` |

Warnings-as-errors is on for the compiling legs, so the green build is a hard
warning gate.

## Diff summary

Pure UI relocation. Five controls (Destination list, Number Reminders, Scaling,
Factor, Show on watch) and their private helpers/state move verbatim from
`ChecklistDetailView` to the new pushed `ChecklistOptionsView`; a
`NavigationLink` row (`checklistOptionsLink`) is added under the name section;
one new localized key (`"Checklist Options"`, 6 languages) plus its
`LocalizationFixtures.requiredKeys` entry; a new `ChecklistOptionsViewTests`
suite. No store, model or identifier was changed.

## Findings

### Blockers
None.

### Fixes worth doing now
None. The reviewer raised no P0/P1 and no actionable correctness defect; both
notes are optional and one is consistent with an existing project convention.

### Optional improvements
1. `CheckStitchTests/ChecklistOptionsViewTests.swift:46` —
   `optionsViewCarriesItsMovedStateSeams` asserts `String(describing:)` contains
   `_store` / `listsSnapshot` / `destinationUnavailable`, i.e. it reflects on
   private `@State` internals. **Ignored/deferred:** this is the established
   project test convention, used six times in
   `CheckStitchTests/ChecklistDetailViewTests.swift` (lines 19, 31, 43, 52, 153,
   261). Changing it here would diverge from the surrounding suites.
2. `ImageRenderer` smoke tests do not run `onAppear`, so `loadReminderLists()`
   and the nil-snapshot `destinationBinding` fallback are not unit-exercised.
   **Deferred:** a pre-existing limitation of the `ImageRenderer` oracle
   (`ViewRenderTests`), unchanged by this diff and out of scope for a UI move.

### Feedback to ignore or defer (summary)
Both of the above. No architecture, concurrency, memory or localization issue
was found.

## Reviewer limitations (recorded for honesty)

The reviewer ran in a sandbox without a shell and with the committed range
invisible to `watchdog_diff`, so it reviewed final file state against the plan
rather than a true diff, and could not run build/test itself. Its green-test
claims were therefore unverified by it; the orchestrator independently ran the
full gate and `l10n-check.sh` (results above) to cover that gap.

## Remaining manual items (from `plan.md`)

- [ ] `make run`: open a checklist, tap **Checklist Options** — the five controls
      appear with existing behaviour; the back button returns to the edit screen.
- [ ] `make run`: the edit screen shows only the name field, the **Checklist
      Options** row and the Items list.
- [ ] Change each option on the options screen, go back, reopen — values
      persisted through `ChecklistStore`.
