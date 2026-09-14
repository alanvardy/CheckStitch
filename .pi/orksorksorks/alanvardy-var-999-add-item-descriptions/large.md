# Task

VAR-999: add an optional free-text description to each checklist item. The description must survive the checklist lifecycle — persisted through the shared envelope codec (App-Group UserDefaults `checklists.v1`, iCloud KVS, and WCSession context bytes, all read/written by the iOS app, macOS slice, and watchOS target), round-tripping decode, merge, and duplicate — and be editable in the iOS `ChecklistDetailView` item editor alongside the existing title, plus surfaced in the watch item rows.

The change spans the `ChecklistItem` model and its custom `Codable` codec (CheckStitchCore), the store (add/update/duplicate), the iOS and watch UIs, backward compatibility with existing persisted v2 payloads, and the item→Reminder mapping; whether the description should ride into created reminders (currently title-only) is an open product decision for the design phase.

## Why LARGE

SCHEMA + CONVENTION_RISK + DESIGN_SIGN-OFF + CROSS_CUTTING + UNKNOWNS: adding `description` to `ChecklistItem` changes the shared persisted/wire envelope with backward-compat and a versioning decision that must not collide with the in-flight var-995 v3 migration, whether it flows into created Reminders is an open product call, and the change touches data model, storage, UI, and platform targets at once.