# Research Questions

## Context

The project is a Swift/SwiftUI iOS app with a sources-only SPM core package
(`CheckStitchCore`) holding the domain models, an app target (`CheckStitch/`)
that contains the persistence store and the single list screen, unit suites
(`CheckStitchTests`, macOS-hosted) plus a UI smoke test, and a watchOS app
(`CheckStitchWatch`) that shares the core model. Focus on the model and
persistence layer, the main list screen and its view model, the sync/merge
surface, and the test/localization conventions.

## Questions

1. How are the checklist domain entities defined, encoded (Codable), and
   persisted in the app-side `ChecklistStore`? What patterns already exist for
   optional/additive fields, tombstones, and the envelope wrapper — i.e. how
   does a newly-introduced optional field on a checklist flow through
   encode/decode and storage today?

2. What is the exact structure of `ContentView`'s main list screen — how does
   it render the checklist list, how do edit mode, the per-row minus control,
   and context/menu actions work, and how are the macOS toolbar create action
   and the iOS edit toggle wired?

3. How do `ChecklistListViewModel` and the store's mutating actions (create,
   remove, move, duplicate) work together, and what observable state/actions
   drive the main list screen?

4. How do `ChecklistSyncCoordinator`, `ChecklistSyncing`, and `ChecklistMerge`
   handle model changes, sync/update fields (revisions, `modifiedAt`), and the
   merge of locally-stored lists — i.e. how would a new relationship field (a
   group/folder id on a checklist) propagate through encode/merge?

5. What are the concrete unit-test patterns and fixtures for the store and
   view model in `CheckStitchTests` (including `TestFixtures.swift`), and what
   are the localization requirements for adding new user-facing string keys
   (`Localizable.xcstrings`, `LocalizationFixtures.requiredKeys`,
   all-language entries)?