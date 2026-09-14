# Research Questions

## Context

CheckStitch is a Swift/SwiftUI iOS app with a shared CheckStitchCore package. Checklist data flows through a custom Codable envelope codec persisted in App-Group UserDefaults under the key `checklists.v1`, synced via iCloud KVS and WCSession context bytes, merged on apply, mutated through a store in the app layer, and rendered in iOS and watchOS views. The `ChecklistItem` model and its codec sit at the heart of this data flow.

## Questions

1. How is the `ChecklistItem` model defined and encoded in CheckStitchCore — what fields, CodingKeys, and encode/decode behavior does its custom Codable implement, and how are absent or unknown keys and `isBlank` handled during decode?

2. How does `ChecklistCodec` classify persisted payload versions (v1 migratable, v2 current, unsupported, unreadable), and what does the store's load/save path do with each classification — including the will-not-overwrite-newer-payload guard?

3. What exactly do the store's item operations (`addItem`, `updateItem`, `duplicate`, `removeItems`, `rename`) set on a `ChecklistItem` — which fields, revisions, and timestamps — and how does duplicate construct its new items from source items?

4. How does `ChecklistMerge` decide winners at the envelope, checklist, and item levels, and what happens to the losing item's fields when an item is replaced?

5. How do the two reminder-creation paths (`ChecklistReminders.create` and the legacy `ChecklistCreator` flow) map item data onto created Reminders, and what do they skip?

6. How does `ChecklistDetailView` render and edit item rows — the title field binding, the update call into the store, and its layout — and how does `ContentView` surface checklists and the create-reminders action?

7. How does the watchOS target render item rows (`WatchChecklistDetailView`), and how does `WatchChecklistStore` receive, decode, and hold the WCSession context bytes pushed from the phone?