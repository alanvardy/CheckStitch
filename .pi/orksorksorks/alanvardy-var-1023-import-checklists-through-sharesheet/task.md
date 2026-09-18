# Task

Build a way for a Checklist file to arrive by email, be shared, and be brought
into Share Sheet (the macOS/iOS universal clipboard / share mechanism), where
the user selects which checklists to import and only those are imported into
CheckStitch/Reminders.

This is a new import subsystem: a Share Sheet reception/integration seam plus a
checklist-file parser, wired through a selection UI and the existing
checklist-to-Reminders creator, that must coexist with CheckStitch's current
export/sync/EventKit scaffolding. Research must establish how file delivery via
the share/share-receive mechanism works today and what import/selection
patterns already exist.