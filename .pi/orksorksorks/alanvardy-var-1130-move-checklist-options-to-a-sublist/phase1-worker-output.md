# Phase 1 Worker Output — VAR-1130 Move checklist options to a sublist

## Task
Implement **Phase 1** of the plan: introduce the **Checklist Options** subscreen
(reachable via a `NavigationLink` row under the checklist-name section of
`ChecklistDetailView`), wire all five controls to their existing `ChecklistStore`
bindings, and add the new "Checklist Options" localized key in all 6 languages
plus its fixture entry. Phase 2 (removing the five controls from the edit screen)
is explicitly **not** in scope for this run and was not touched.

## Changes made

1. **Created `CheckStitch/ChecklistOptionsView.swift`** — the pushed options
   screen replicating the five controls (Destination list, Number Reminders,
   Scaling, Factor, Show on watch) plus the moved `ScalingMode` enum and every
   binding/state helper (`loadReminderLists`, `destinationIsStale`,
   `numberingBinding`, `scalingModeBinding`, `multipleBinding`, `scalingField`,
   `showOnWatchBinding`, `destinationBinding`). Uses the named `Form` +
   `settingsSubscreenLayout()` precedent. No `project.pbxproj` edit needed
   (`PBXFileSystemSynchronizedRootGroup`).

2. **Modified `CheckStitch/ChecklistDetailView.swift`** — inserted a new section
   with a `NavigationLink` to `ChecklistOptionsView(checklistID:)`, labelled
   "Checklist Options" with `slider.horizontal.3`, accessibility id
   `checklistOptionsLink`, immediately after the "Checklist name" section and
   before the Destination section. The five controls remain on the edit screen
   (Phase 2 only).

3. **Modified `CheckStitch/Localizable.xcstrings`** — added the `"Checklist
   Options"` key with all 6 translations (en, de, es, fr, ja, zh-Hans), inserted
   alphabetically between "Checklist not found" and "Choose between system...".

4. **Modified `CheckStitchTests/LocalizationFixtures.swift`** — added
   `"Checklist Options"` to the `requiredKeys` "App" entry in the alphabetical
   gap.

5. **Created `CheckStitchTests/ChecklistOptionsViewTests.swift`** — `@MainActor`
   Swift Testing suite (3 tests) using the `ImageRenderer` body oracle from
   `ViewRenderTests` plus `String(describing:)` seam checks.

## Validation

- `scripts/l10n-check.sh` → **ok** (4 catalogs, 194 keys, 6 languages).
- `make build` (simulator) → **BUILD SUCCEEDED** (warnings-as-errors clean).
- `make test-unit` (macOS) → **674 tests in 70 suites passed**; the new
  `ChecklistOptionsViewTests` suite passed (3 tests).

## Notes
- No staged files (changes are working-tree only).
- Phase 2 removal of the five controls/helpers from `ChecklistDetailView` is not
  done (out of scope for Phase 1 per plan).
- No residual risks observed; automated and manual verification per the plan's
  Phase 1 checklist is satisfied.
