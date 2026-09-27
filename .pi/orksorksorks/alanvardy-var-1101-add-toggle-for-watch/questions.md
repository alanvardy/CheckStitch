# Research Questions

## Context

The codebase is an iOS app (CheckStitch) that creates Reminders checklists from
user-managed lists. Checklist/list-item/folder models live in a local SPM
package (CheckStitchCore) and are versioned + encoded into an envelope that
syncs through iCloud (NSUbiquitousKeyValueStore) and to a watchOS app
(CheckStitchWatch) via WatchConnectivity. Focus on: the versioned envelope
codec and its field-decoding conventions, the iOS edit-checklist forms and how
their controls mutate the store, and how checklist/folder/item data flows to
and renders in the watch app.

## Questions

1. How does the versioned `ChecklistEnvelope` codec store boolean fields on
   `ChecklistItem`, `Checklist`, and `Folder`, including their decode defaults
   when a key is absent from older data, and under what conditions does the
   codec bump `currentVersion` versus rely on `decodeIfPresent` defaults /
   `migrated(at:)`? (codebase-analyzer)

2. What patterns exist in the iOS edit-checklist screens for boolean toggle
   controls, and how do those controls bind to and invoke store mutation
   methods? Trace the full path for an existing `Toggle` (e.g. the Number
   Reminders toggle) from view → binding → store method → persisted field.
   (codebase-pattern-finder)

3. How does data flow from the phone to the watch layer, and how do the watch
   views (main list, folder detail, checklist detail) resolve and render
   checklists, folders, and items from the received envelope? Where does a
   per-checklist boolean flag become visible to the watch rendering layer, and
   where are items filtered into a displayed list? (codebase-analyzer)

4. How is folder membership modeled and resolved (e.g. `folderID` on a
   Checklist), and how do the watch views enumerate a folder's child checklists
   for the folder detail view? How would the rendering layer know the set of
   checklists that belong to a given folder when deciding what that folder
   shows? (codebase-analyzer)

5. What is the convention for adding a new user-facing string key across the
   6-language String Catalog(s) and the `LocalizationFixtures.requiredKeys`
   test fixture — which catalogs exist, which one a given UI string belongs to,
   and what the language/key check enforces? (codebase-pattern-finder)

6. How are the data-model codec decode-default and version behaviors, and the
   view-level toggle behaviors, covered by tests — which test files exist, what
   cases they cover, and how platform gating (`#if os(...)`, `@MainActor`) is
   applied? (codebase-pattern-finder)

For each question: Describe what exists. Do not suggest improvements or propose
solutions.
