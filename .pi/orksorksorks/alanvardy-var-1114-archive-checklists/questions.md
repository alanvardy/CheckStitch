# Research Questions

## Context

These questions map the CheckStitch persistence, sync, run, query, UI, localization, and test layers. Focus areas: the Checklist data model and ChecklistCodec; the ChecklistStore mutation/naming/tombstone machinery; the ChecklistMerge LWW convergence; the run/intent/entity-query and widget paths; the grouping/main-list/Settings/export surfaces; the 6-language localization setup; and the test-suite organization and platform gating. All findings should be neutral — describe what exists, with `file:line` references, never proposing changes.

## Questions

1. How is the Checklist data model structured and how does ChecklistCodec encode/decode it — specifically how additive optional keys are decoded (`decodeIfPresent`), how `encode` writes fields (unconditional vs conditionally), and how version classification (`unsupportedVersion`, `loaded`, `migratable`) decides what happens to a payload? How would a new additive field on `Checklist` be carried through encode/decode and what are the consequences of not bumping `version`?

2. How does ChecklistStore implement its mutating operations and shared primitives — the coarse `revision`/`modifiedAt` clock (and how `rename`, `setDestination`, `moveChecklist`, `delete` bump it), tombstone creation/`revision + 1` on delete, `save()`/`scheduleSave`/debounce, name-uniqueness via `uniqueName`/`conflictingChecklist`/`sameName`, and the import `freshCopy` path (Keep Both vs Replace)? Which existing operations would an archive/restore/removeArchived follow in shape?

3. How does ChecklistMerge.mergedChecklists converge two device states — the symmetric LWW winner rule, tombstone handling, coarse-vs-per-field clocks, and how a field record present in one snapshot but absent in another is reconciled? Where would a new boolean/date field on Checklist flow through the merge?

4. How do the run and query paths work — how `RunChecklistIntent` resolves a checklist id (and the `checklistNotFound` path), how `ChecklistEntityQuery.entities`/`entities(matching:)`/`suggestedEntities` source their models, and how the widget (`ChecklistWidgetLoader`, `hasChecklists`, the display model) and the run path enumerate checklists?

5. How does each UI surface enumerate or filter checklists — `ChecklistGrouping.visibleLooseChecklists`/`visibleChecklists`/`visibleFolders` and the `showsOnWatch` filter, the main list (`ContentView`, `ChecklistListViewModel`, folder groups, empty states), the export surface (`ExportChecklistsView`, export VM/selection), Settings (`SettingsView`/`SettingsViewModel`/`SettingsBindings`, subscreen and `settingsSubscreenLayout` pattern), and `ChecklistDetailView`? What is the shared filtering convention across these surfaces?

6. How does localization work — where the app/`Core` catalogs live, the 6 languages, `Localizable.xcstrings` key structure, `LocalizationFixtures.requiredKeys` / `guardedCatalogs`, `scripts/l10n-check.sh`, and the existing pluralized-message precedent (`"%lld days ago"` style)? What does adding a new key in all 6 languages plus a fixture entry require end to end?

7. What is the test-suite organization and its conventions — where the store/codec/merge/widget/query/localization suites live, what each covers, their platform gating (macOS-hosted Swift Testing, `@MainActor`, XCTest smoke), and how they are run (`make test-unit`, `make test-ui`, the full `scripts/test.sh` gate)?