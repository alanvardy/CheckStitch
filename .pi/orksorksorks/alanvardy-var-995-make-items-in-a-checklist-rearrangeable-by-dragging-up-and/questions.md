# Research Questions

## Context
Focus on the CheckStitch app target (CheckStitch/) and the CheckStitchCore
package: the checklist store, the checklist edit-screen view, the checklist
merge algorithm, the checklist data model and its JSON codec, the iCloud
key-value sync pipeline, and the test suites that cover these. Describe what
currently exists in each area and how the pieces connect end to end; do not
propose changes.

## Questions

1. How does the ChecklistStore mutation API work: what methods exist, their
   signatures and return types, how revision and modifiedAt are stamped on
   items and checklists, what IndexSet means in the removeItems method, and
   how are changes persisted and debounced through the save path?
   (CheckStitch/ChecklistStore.swift)

2. How does the checklist detail/edit screen render and mutate the item
   list: what SwiftUI container and item loop are used, how do the per-item
   title bindings reach the store, how are add, delete-on-select and rename
   wired, and what happens on view disappear?
   (CheckStitch/ChecklistDetailView.swift)

3. How does the checklist merge algorithm combine local and remote
   envelopes: what orderings does it preserve, how are conflicting items and
   checklists won, what role do revisions, timestamps and deviceID play, and
   how do tombstones and remote-only items flow into the result?
   (CheckStitch/ChecklistMerge.swift)

4. What is the checklist data model and its encoding: the fields and
   identity of ChecklistItem and Checklist, the Codable encode/decode
   protocol, ChecklistCodec versioning, classification and migration, and
   every place an item's persisted byte representation is touched?
   (CheckStitchCore/Sources/CheckStitchCore/Checklist.swift)

5. How does the iCloud sync pipeline work end to end: how does
   ChecklistSyncService reconcile, push and debounce, how does
   UbiquitousChecklistSync wrap NSUbiquitousKeyValueStore, how is
   ChecklistMerge invoked from the store apply path, and what exactly does
   contentEquals compare, including list order?
   (CheckStitch/ChecklistSyncService.swift,
   CheckStitchCore/Sources/CheckStitchCore/ChecklistSyncing.swift)

6. What test suites and fixtures cover the store, merge, model, codec and
   sync: which files, which test styles, what fakes exist, how IndexSet and
   persistence-reload cases are tested, and are there any existing SwiftUI
   drag/reorder affordances (for example onMove or onReorder) anywhere in
   the repo?