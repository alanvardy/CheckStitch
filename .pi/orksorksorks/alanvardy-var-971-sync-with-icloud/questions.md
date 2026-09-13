# Research Questions

## Context

This repo is a small Swift/SwiftUI iOS app. Checklist data lives in a local
UserDefaults-backed store in the app target; reminder creation touches iOS
Reminders through EventKit, with a seam in the CheckStitchCore SPM package
and a parallel app-target path. The reference app at
/Users/vardy/dev/SingleThread shares the same Reminders/EventKit integration
approach and is the pattern source for this project. The questions below map
the data model, persistence lifecycle, EventKit interactions, UI layer,
reference-app patterns, test conventions, and signing configuration.

## Questions

1. (codebase-analyzer) Trace the checklist data flow end to end in
   /Users/vardy/dev/alanvardy-var-971-sync-with-icloud: where checklist and
   item models are defined (app target and CheckStitchCore), every read and
   write site, the codec that encodes and classifies stored payloads, and
   the UserDefaults App Group storage lifecycle (load, coalesced save,
   flush, delete). Report what identifiers or revision/change markers each
   model carries.

2. (codebase-analyzer) Trace both Reminders-creation paths in the repo: the
   ReminderCreating protocol and EventKitReminderCreator in CheckStitchCore,
   and ChecklistReminders in the app target. Report the EKEventStore
   lifecycle in each, the permission flow, the save(commit:) pattern, the
   outcome types returned, and how outcomes reach UI state. Note every place
   EventKit is used for reading, fetching (predicates/calendars), or
   observing reminders, if any.

3. (codebase-analyzer) Trace the UI layer: ContentView, ChecklistDetailView,
   MyApp, and the ChecklistViewModel. Report what state each exposes, how
   views trigger actions, how creation feedback is shown and dismissed, and
   enumerate every existing refresh, reload, or state-update mechanism in
   the UI (including any .refreshable or pull-to-refresh usage).

4. (codebase-pattern-finder) Survey the reference app at
   /Users/vardy/dev/SingleThread: find every place EventKit/Reminders is
   used — creating reminders, fetching them (predicates, calendars,
   defaultCalendarForNewReminders), reading back previously created state,
   observing changes or notifications between app runs, and permission
   handling. Report each use with file:line references.

5. (codebase-pattern-finder) Survey test conventions in
   /Users/vardy/dev/alanvardy-var-971-sync-with-icloud: how EventKit is
   faked or stubbed across CheckStitchTests, the inventory of every test
   file and what it covers, platform gating, and the canonical build/test/
   run commands defined in the Makefile and scripts/ (test.sh,
   run-devices.sh, run-simulator.sh), with file:line references.

6. (codebase-locator) Locate signing and configuration: entitlements files
   (App Group usage) in CheckStitch and in /Users/vardy/dev/SingleThread,
   all INFOPLIST_KEY_* and GENERATE_INFOPLIST_FILE settings in
   project.pbxproj, any iCloud/CloudKit/ubiquity-related entitlements or
   capabilities in either project, and every App Group identifier used.