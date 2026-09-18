# Task

Build a way for a Checklist file to arrive by email, be shared, and be brought
into Share Sheet (the macOS/iOS universal clipboard / share mechanism), where
the user selects which checklists to import and only those are imported into
CheckStitch/Reminders.

## Why LARGE
NEW_SURFACE + CROSS_CUTTING: this is a new import subsystem (a Share Sheet
reception/integration seam and a checklist-file parser), wired through a
selection UI and the existing checklist→Reminders creator, that must coexist
with CheckStitch's current export/sync/EventKit scaffolding — requiring
research on exactly how file delivery via the share sheet works and a
product/design decision on the import-and-select flow.