# Research Questions

## Context

This survey covers the CheckStitch Swift/SwiftUI codebase (app target,
CheckStitchCore, tests, scripts) around: how files are received and imported,
how the app is registered as a handler for incoming intents/shares, how a
checklist becomes Reminders reminders, what multi-select/list-selection UI
patterns exist, and the on-disk checklist wire format plus its import test
patterns. Describe what exists; do not suggest improvements or propose
solutions. Cite file:line references and keep the report under 100 lines.

## Questions

1. Trace the existing file-import data flow end to end: from file bytes
   arriving (importFile / importFile(at url:) in the import-export view
   model) through ChecklistImportSession decode, the
   ChecklistImportCandidate list, the FIFO conflict queue, ImportDecision
   values (replace / keepBoth / keepExisting), ImportSummary and
   ChecklistImportError. What file formats are accepted, how is the read
   security-scoped, and what are the conflict semantics?

2. How does the platform intent / share / receive mechanism work? Trace
   CheckStitch/Intents/ (ChecklistEntity, ListChecklistsIntent,
   RunChecklistIntent, CheckStitchShortcuts), how the app registers itself
   as a handler for incoming intents or files, and any file-receive or
   share-target wiring (including how a received file or URL is validated or
   secured). What is the entry point by which the OS hands a shared file or
   intent to the app on macOS and iOS?

3. Trace how a checklist travels from the domain model to a Reminders
   reminder: the ChecklistCreator plus ReminderCreating / EventKitReminderCreator
   (requestAccess, create, defaultCalendarForNewReminders, save commit true),
   the ReminderDestinationTargeting seam and EventKitReminderDestination,
   and how CheckStitch/ChecklistReminders validates a destination before any
   create. What constraints apply per item (blank titles dropped, prefix
   numbering, due date, priority)?

4. What multi-select / list-selection UI patterns already exist? Survey
   ExportChecklistsView and ChecklistImportExportViewModel (the export
   multi-select and conflict decisions), how the root ContentView switches
   screens via NavigationStack, and how a list of checklists is rendered and
   user choices collected (sheet, checkboxes, selection rows). How is
   imported-file feedback and error surfaced to the user?

5. What is the checklist export wire format and its round-trip, and how are
   imports tested? Cover ChecklistEnvelope and ChecklistCodec (currentVersion,
   classify/encode/decode), ChecklistExport.filename()/data(), ChecklistItem
   field encodings, and the test patterns in ChecklistImportSessionTests,
   ChecklistImportExportViewModelTests, ChecklistCodecTests and
   ChecklistExportTests (fixtures, byte samples, @Test(arguments:) cases,
   @MainActor gating).