# Task

Sync all checklist data with iCloud so that the set of checklists and their
items (members) round-trips across devices, and add a manual "pull down to
refresh" force-refresh of the sync state, following the behaviour already
implemented in the reference app at /Users/vardy/dev/SingleThread (its
EKReminder + defaultCalendarForNewReminders() + save(commit: true) pattern,
and NSReminders*UsageDescription keys).

The work spans the checklist data model (per-list sync state, identifiers,
revisions), a new sync integration layer in CheckStitchCore's EventKit seam,
a UI-surface change in CheckStitch/ContentView.swift (pull-to-refresh), plus
open questions on what exactly is synced, conflict handling, and migration
of existing local checklists before first sync.