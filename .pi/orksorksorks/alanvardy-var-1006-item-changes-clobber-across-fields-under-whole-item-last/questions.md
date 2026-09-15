# Research Questions

## Context

The checklist item model (title, description, relativeDate, revision,
modifiedAt), the conflict-merge logic (`ChecklistMerge`), the persistence
codec and store, the EventKit/KVS sync seam and reconcile service, and the
test suites covering merge, codec, and sync. The app source lives in
`CheckStitch/`, core types in `CheckStitchCore/`, tests in `CheckStitchTests/`
and `CheckStitchUITests/`.

## Questions

1. How does `ChecklistMerge` resolve conflicts, and what exactly does it copy
   for a winner? Trace the merge algorithm: the `wins` comparator (revision,
   modifiedAt, device id), the per-item merge path, the checklist-level
   (name, destinationListIdentifier) merge, the order
   (orderRevision/orderModifiedAt) merge, and tombstone unioning/suppression.
   For each level, give `file:line` and the exact comparison and copy
   performed.

2. What are the semantics and lifecycle of per-item sync state (`revision`,
   `modifiedAt`) and of delete/tombstone state? Where in the store is
   `revision`/`modifiedAt` bumped for each mutation type (create, rename,
   updateItem title, updateItemDescription, updateItem relativeDate,
   removeItems, delete), what counts as an edit, what values are assigned,
   and how do tombstones (`ChecklistTombstone` revision, deletedAt)
   interact with live items during merge and in the codec?

3. How does the codec serialize and parse `ChecklistItem`, `Checklist`,
   `ChecklistEnvelope`, and `ChecklistTombstone`? List every coding key
   written per type, every decoder default, how versioning works
   (`currentVersion`, `classify`, migration paths v1–v4, unknown and
   undecodable handling), and the backward-compatibility mechanics (what
   happens when a store or sync participant sees bytes with fewer or more
   keys).

4. What is the end-to-end path of an item edit from the UI to a remote
   device's store? Trace: `ChecklistDetailView` bindings → store mutator →
   scheduleSave/encode → KVS (`UbiquitousChecklistSync`) → remote →
   `didChangeExternallyNotification` → `ChecklistSyncService.reconcileNow`
   → `store.apply(remote:)` → merge invocation site, with `file:line`;
   also describe the guards (`canOverwriteStoredPayload`, `contentEquals`,
   version mismatch, unknown/unreadable remote bytes) and who calls
   `mergedItems`.

5. What do the merge/codec/sync test suites actually cover? Inventory
   `ChecklistMergeTests`, `ChecklistCodecTests` (VAR-969 XCTest),
   `ChecklistStoreTests`, `ChecklistSyncServiceTests`, and any
   sync-coordinator/KVS tests: suite struct names, platform gating, the
   scenarios each covers (LWW wins, tombstones, ids, v1/v2/v3 migration,
   unknown versions, round-trips, idempotence), and how tests inject time
   and compare results.

6. Which code paths mutate each item text field (title, description) and the
   date field, and how do they differ? Map every store mutator and UI
   binding per field, what each passes, and where relativeDate vs title vs
   description diverge (e.g. no-op on unchanged value).