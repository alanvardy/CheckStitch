# Research Questions

## Context

Explore the CheckStitch codebase areas: the core data model and its mutation
conventions (Checklist.swift, ChecklistStore.swift), the persistence codec and
merge round-trip, the reminder-creation run paths and title numbering resolver
(ChecklistCreator.swift, ChecklistReminders.swift), the read-only vs editing UI
surfaces across iOS/macOS/watch/widget, the App Intents contract
(RunChecklistIntent.swift and siblings), and export/share/import plus
localization fixtures. The `((n))` positional-marker replacement does NOT yet
exist — treat all of this as reporting what already exists.

## Questions

1. How are mutable scalar fields on `Checklist` and `ChecklistItem` declared
   and mutated? Describe the no-op-guard + `revision`/`modifiedAt` bump
   convention, where setters/bindings live, and the trio of places a new scalar
   field must touch (model declaration, codec, mutation entry point).

2. How does a checklist scalar field round-trip through the persistence codec
   and merge? Describe `encode`/`decode` (`decodeIfPresent ?? default`), the
   `ChecklistEnvelope`, format versioning, and how `ChecklistMerge`
   (`ChoklistMerge.swift`) reconciles fields (which side wins, per-field
   revision/date `wins`).

3. How does the reminder-creation flow get from a checklist to instantiated
   reminder items? Trace `ChecklistTitleNumbering` (its pure
   `title(_:position:numbered:itemCount:)` resolver), both run paths
   (`ChecklistCreator.create`, `ChecklistReminders.create`), `RunCounter`, and
   call sites — where raw titles/descriptions are read and where any derived
   text is produced.

4. How do read-only versus editing surfaces render checklist/item text across
   iOS, macOS, watch, and widget? Identify the read-only row (`ItemRow`
   `displayTitle`), the editor (`ItemEditView`), list-row badge/overlay
   patterns, and which surfaces show raw versus derived text.

5. What parameter and validation patterns do the App Intents follow? Describe
   `RunChecklistIntent`'s `@Parameter` fields, error/validation enum shapes
   (`.invalid...`, `LocalizedError`), the ordering of validation vs side effects in
   `perform`, and how sibling intents (`ListChecklistsIntent`,
   `ChecklistConfigurationIntent`, `MultiChecklistConfigurationIntent`) declare
   optional/custom parameters.

6. How are checklist fields threaded through export, share, import, and
   duplicate/freshCopy? Trace `ChecklistExport`, `ChecklistShare`,
   `ChecklistImportSession`, and `ChecklistStore.duplicate`/`freshCopy`. Also
   describe the localization baseline: `Localizable.xcstrings` structure and the
   `LocalizationFixtures.requiredKeys` pattern a new key must join.