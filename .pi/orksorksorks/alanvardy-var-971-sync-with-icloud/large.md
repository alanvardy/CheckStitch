# Task

Sync all checklist data with iCloud — the number of checklists and their
members (items) must round-trip across devices — and add a manual "pull down
to refresh" force-refresh of the sync state, following the behaviour already
implemented in the reference app at `/Users/vardy/dev/SingleThread` (its
`EKReminder` + `defaultCalendarForNewReminders()` + `save(commit: true)`
pattern, and `NSReminders*UsageDescription` keys).

## Why LARGE

SCHEMA + NEW_SURFACE + CROSS_CUTTING + UNKNOWNS: syncing the checklist set and
its members out of a single-local-store app means a data-model change
(per-list sync state/identifiers/revisions), a new iCloud sync integration
layer in CheckStrictCore's EventKit seam, UI-surface changes
(`ContentView.swift` pull-to-refresh), plus open questions on what exactly is
synced, conflict handling, and migration of existing local checklists before
first sync — no existing pattern in this repo carries the change end to end.