# Research Questions

## Context

CheckStitch is a Swift/SwiftUI app: `CheckStitchCore` holds the checklist model, a versioned JSON codec, and a tombstones-based envelope; the app layer adds a persistence store, iCloud sync, and the main/detail views. Relevant areas are the core codec and model, the store and sync service in the app layer, the main list and detail views, any platform file export/import or share APIs in this repo or its reference implementation, and the test suites covering codec, store, and sync behavior.

## Questions

1. How does `ChecklistCodec` encode, decode, and classify payloads — what is the envelope format, how are versions probed, and what do the `loaded` / `migratable` / `unsupportedVersion` / `unreadable` outcomes mean in code? Focus on `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift` and any codec tests.

2. How does `ChecklistStore` read, mutate, and persist checklists — exact semantics of `sameName`, `delete` and tombstone recording, `save` and `onChange` wiring, `canOverwriteStoredPayload`, and `apply(remote:)`? Focus on `CheckStitch/ChecklistStore.swift` and its tests.

3. How does `ChecklistSyncService` observe store changes and push or merge — `start()` wiring, `schedulePush` vs `pushNow`, the reconcile flow, and what happens after a store mutation like a delete or add? Focus on `CheckStitch/ChecklistSyncService.swift` and `CheckStitch/ChecklistSyncing.swift`, plus sync tests.

4. How is the main checklist list screen structured, and how are checklist-level actions presented and wired — row rendering, toolbars and menus, navigation, any selection state, and the delete/duplicate/rename confirm dialogs in the detail view? Focus on `CheckStitch/ContentView.swift` and `CheckStitch/ChecklistDetailView.swift`.

5. What platform file export/import and share APIs are used in this repo, in the SingleThread reference implementation, or otherwise known to the platform — `.fileExporter`, `.fileImporter`, `ShareLink`, document or attachment creation, save/open panel patterns, and filename conventions? Focus on `/Users/vardy/dev/alanvardy-var-997-import-and-export-checklists-as-json` and `/Users/vardy/dev/SingleThread`.

6. How are the existing test suites structured for codec round trips, store mutations and tombstones, sync behavior, and rejection of bad payloads — which test frameworks, which platform gating, and what assertion styles do they use? Focus on `CheckStitchTests/` and `CheckStitchUITests/`.