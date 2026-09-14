# Research Questions

## Context

The CheckStitch codebase has five areas of interest: the per-item data model
in CheckStitchCore and its Codable wire encoding, the versioned checklist
envelope with its store/merge/sync layers (iOS + watch), the checklist-detail
UI that edits one row per item, the Reminders/EventKit creation paths (live
and core mirror), and date/calendar primitives used anywhere in the repo.
Describe what exists in each area; do not suggest improvements or propose
solutions.

## Questions

1. How does the ChecklistItem Codable encoding work, and how does the
   versioned ChecklistCodec handle old, current, and unknown envelope
   versions? Specifically: the generic Codable/CodingKey mechanism
   (CustomCodingKey, decodeIfPresent, CodingKey), how a field's absence is
   handled on decode, what ChecklistCodec classify() does for versions 1, 2
   and unknown, how the v1-to-v2 migration was performed, and where
   canOverwriteStoredPayload gets set and what it gates.

2. What is the complete path of an item edit and of a remote payload? Trace
   the UI binding call into the store (updateItem), save scheduling and the
   KVS write (checklists.v1 key), then the remote side — ChecklistSyncService
   reconcile, store.apply, ChecklistMerge LWW merge and tombstone union,
   envelope contentEquals — and finally the watch decoder path
   (ChecklistSyncMessage context handling in WatchChecklistStore). Which
   fields feed LWW winners, what state is persisted, and what happens when a
   decode encounters unknown or malformed content?

3. How does ChecklistDetailView render and edit one row per checklist item?
   Describe the row construction (TextField per item), the titleBinding
   get/set mechanics, how text edits are committed through the store, the
   accessibility-id naming conventions used across the app's views, and how
   ChecklistDetailViewTests exercise the view.

4. How is reminder creation implemented, in both the live path and the core
   mirror? Describe ChecklistReminders.create (EKEventStore,
   requestFullAccessToReminders, EKReminder construction,
   defaultCalendarForNewReminders, save commit), the ReminderCreating
   protocol, EventKitReminderCreator, ChecklistCreator.create flow, and
   ChecklistViewModel — which fields are set on the reminders, what the
   EventKit seam exposes, and how tests inject fakes.

5. What date and calendar primitives exist in the codebase and in the
   SingleThread reference repo at /Users/vardy/dev/SingleThread? Look for
   Calendar.current, DateComponent(s), dateComponents, date arithmetic or
   formatting, any EKReminder date/time fields being set, and timezone
   handling — where they are used, and what the EKReminder/EKEventStore types
   offer. Note any tests covering dates or calendars.