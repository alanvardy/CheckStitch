# Research Questions

## Context

How CheckStitch models checklists and their items and persists them; how a
checklist's items become Reminders through the EventKit seam, including
permission, destination, and partial-failure states; how the app is declared
and launched at the platform level (entitlements, infoplist, delegate
adaptors, os-gated targets); how the app surfaces user-facing error and status
text today; and how all of this is tested.

## Questions

1. [codebase-analyzer] Trace the end-to-end flow that creates reminders for a
   checklist's items, from the public entry points to the EventKit save. How
   is reminder access requested (status check vs. a prompt — what does the
   call do and return), how is the target calendar chosen, and what exact
   failure and partial-creation states can occur, including mid-loop
   failures? What outcome/error value carries each state, and how do
   consumers (ContentView) read it?

2. [codebase-analyzer] What operations does ChecklistStore expose for reading
   and modifying checklists (enumeration, lookup, rename, delete)? What are
   the identity and lifecycle semantics of rename and delete — is the
   checklist id stable, what happens to tombstones and sync state, and how do
   other views (ContentView list, settings, export/import, sync) consume the
   store?

3. [codebase-pattern-finder] Survey how per-item and per-checklist settings
   flow onto a created reminder: for each item setting (title, description,
   relative date / due-date components) and each checklist setting
   (destination list / calendar), find the exact code mapping it onto the
   created reminder (title, notes, calendar, due-date fields), and any code
   path where a setting exists on the item but is not copied through.

4. [codebase-analyzer] Describe the app's launch and platform-declaration
   surface: the @main App struct, its delegate adaptors, window/scene
   lifecycle hooks, the AppGroup entitlements and infoplist declarations
   (including the NSReminders usage-description keys — where their text lives
   and per-target declarations), bundle-id and platform settings across
   targets, and any mechanism today by which external input could reach the
   app (URLs, notifications, command-line, OS events). Include how the watch
   target reuses CheckStitchCore and what is excluded via os-gating.

5. [codebase-pattern-finder] Survey all user-facing error and status messages
   the app can present today: where message strings live (Swift literals,
   per-locale localization files, NSReminders keys), the conventions for
   alert titles/bodies and control identifiers in ContentView, how software
   tests assert on these strings, and the exact ReminderRunOutcome
   errorMessage values and the alerts or views they drive.