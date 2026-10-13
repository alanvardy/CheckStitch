# Phase 2 Worker Output — VAR-1130 Move checklist options to a sublist

## Task
Complete the relocation started in Phase 1: remove the five moved controls and
their now-dead private state/helpers from `ChecklistDetailView`, leaving the
edit screen with only the name field, the **Checklist Options** link row and
the Items list. The five controls (Destination list, Number Reminders,
Scaling, Factor, Show on watch) already live on `ChecklistOptionsView` with
unchanged `ChecklistStore` bindings and accessibility identifiers, so this
phase is a pure deletion with no behaviour change.

## Changes made

**Modified `CheckStitch/ChecklistDetailView.swift`** only:

1. Deleted the file-scope `private enum ScalingMode`.
2. Deleted `@State private var listsSnapshot` and
   `@State private var destinationUnavailable` (with their doc comments).
3. Deleted the five `Section`s — Destination list, Number Reminders, Scaling,
   Show on watch (the Scaling section also hosted the Factor field). The
   remaining form is: "Checklist name", the Checklist Options link section,
   `Section("Items")` and the existing action buttons.
4. Removed the dead `Task { await loadReminderLists() }` from `.onAppear`,
   leaving only the draft-name seeding.
5. Deleted the now-unreferenced private helpers: `loadReminderLists`,
   `destinationIsStale`, `numberingBinding`, `scalingModeBinding`,
   `multipleBinding`, `scalingField`, `showOnWatchBinding`,
   `destinationBinding`.

No `project.pbxproj` edit and no other file change was needed; Phase 1 already
created the options screen, the link, and the localization entry.

## Validation

- `rg -n 'ScalingMode|listsSnapshot|destinationUnavailable|loadReminderLists|destinationIsStale|scalingField|numberingBinding|multipleBinding|showOnWatchBinding|destinationBinding|scalingModeBinding' CheckStitch/ChecklistDetailView.swift`
  → **no matches** (no unused-private/dead-code references remain).
- `make build` (simulator) → **BUILD SUCCEEDED** (warnings-as-errors clean).
- `make test-unit` (macOS) → **674 tests in 70 suites passed**, including the
  existing 28 `ChecklistDetailViewTests` and the Phase 1
  `ChecklistOptionsViewTests` suite.
- `bash scripts/test.sh` → prints **`gate: ok`** (26 shell tests passed,
  build-mac/watch-build legs succeeded).

## Notes
- No staged files (changes are working-tree only).
- Manual `make run` verification (navigate to Checklist Options, change
  values, confirm persistence) is not run here; the automated gate is green and
  the controls' store bindings are byte-for-byte the ones moved in Phase 1.
- No residual risks observed.
