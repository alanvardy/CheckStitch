# Task

Items in a CheckStitch checklist can carry an optional relative date: an
integer where 0 means today, 1 means tomorrow, and so on. An item with no
number has no date. Times are not supported. The relative date must be
editable per item alongside its name, must survive persistence/sync, and —
when a checklist is run — must be applied to the reminder created for that
item as a date-only due date (today + offset, local calendar), rather than the
current always-no-date behavior.

## Why LARGE

Triggers: **SCHEMA** (a new persisted field on `ChecklistItem`, which lives in
the versioned `ChecklistEnvelope`/KVS `checklists.v1` wire format synced via
iCloud and watch, guarded by `canOverwriteStoredPayload` — the compatibility
change needs design) and **CONVENTION_RISK** (shared persistence/sync format
across iOS + watch + merge with backward-compatibility decisions, e.g.
envelope version bump vs. leave), plus **CROSS_CUTTING** (field flows
model → UI surface → EventKit reminder creation; the relative-offset →
date-only due-date shape is new to this repo, and there is a dormant
`ReminderCreating`/`ChecklistCreator`/`ChecklistViewModel` core mirror whose
date support is a design question).

Key context from recon (design/research should verify):
- `ChecklistItem` lives in `CheckStitchCore/Sources/CheckStitchCore/Checklist.swift:1-50` with custom Codable keys (`id, title, modifiedAt, revision`) and `decodeIfPresent` defaults; a new optional field would be an extra CodingKey, but envelope versioning (`ChecklistCodec`, `currentVersion = 2`) and the store's newer-version overwrite guard must be reasoned about.
- Persistence: `CheckStitch/ChecklistStore.swift` (`defaults.data(forKey: "checklists.v1")`, `save()`), whole-item LWW merge in `CheckStitch/ChecklistMerge.swift`, sync payloads via `UbiquitousChecklistSync` and watch `ChecklistSyncMessage`.
- UI: only item editor is `CheckStitch/ChecklistDetailView.swift` (per-row `TextField` + `titleBinding(checklistID:itemID:)` pattern, `store.updateItem`); a tri-state (no number / integer) relative-date control slots into that row. Accessibility-id convention applies.
- Reminder creation: `CheckStitch/ChecklistReminders.swift:10-29` (`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`, never sets a date); phone side of watch requests wired in `CheckStitch/MyApp.swift:67`. Reference for date-only due dates: `/Users/vardy/dev/SingleThread` (`EventKitStoring.makeReminder`, `ReminderStore.addReminder`/`rescheduleReminder`, `Calendar.current.dateComponents([.year,.month,.day], from:)`).
- Dormant core seam: `CheckStitchCore/Sources/CheckStitchCore/ReminderCreating.swift` + `ChecklistCreator.swift` + `ChecklistViewModel.swift` (test-only consumers) — decide whether it gains date support or stays title-only.
- Watch: no UI change needed (only lists titles), compiles the core model; a new optional field must not break its decode path.
- Test surface touched: `ChecklistItemTests`, `ChecklistCodecTests`, `ChecklistStoreTests` (32), `ChecklistCreatorTests`/`ChecklistViewModelTests`/`EventKitReminderCreatorTests`, `ChecklistDetailViewTests`, plus the UI smoke and sync suites.