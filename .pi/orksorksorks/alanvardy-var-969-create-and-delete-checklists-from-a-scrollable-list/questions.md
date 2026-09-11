# Research Questions

## Context

Focus on the CheckStitch iOS app source and build tooling in
/Users/vardy/dev/alanvardy-var-969-create-and-delete-checklists-from-a-scrollable-list
(CheckStitch/ContentView.swift, CheckStitch/MyApp.swift,
CheckStitch/AppGroup.entitlements, Makefile, scripts/), the Reminders/EventKit
reference repo /Users/vardy/dev/SingleThread, any storage or App Group container
APIs available on this machine (iOS SDK headers, other repos under
/Users/vardy/dev), and the repo's git history. Describe what exists and how it
works; do not suggest improvements or propose solutions.

## Questions

1. Trace the entire current app flow in CheckStitch/ContentView.swift and
   CheckStitch/MyApp.swift: the full SwiftUI view tree, every @State field and
   how it mutates, the edit-overlay (EditChecklistView) presentation and
   dismissal lifecycle including how @Binding works there, the
   createChecklistReminders() flow with its state transitions, and what the
   Remove Checklist and Done buttons do today.

2. How does the Reminders/EventKit integration work end to end, in
   CheckStitch/ContentView.swift and in the reference repo
   /Users/vardy/dev/SingleThread? Cover EKReminder usage,
   defaultCalendarForNewReminders(), eventStore.save(commit: true), the
   NSReminders*UsageDescription keys and where they are defined, which
   reminder fields are set, and how reminder deletion (if any) is done in
   either repo.

3. What App Group container storage exists on this machine for Swift apps:
   what CheckStitch/AppGroup.entitlements grants, the iOS SDK container API
   surface available in the local SDK headers (NSFileManager container
   methods, container sessions), any Swift or other code under
   /Users/vardy/dev that reads or writes container storage, and any repo that
   looks like a CheckStitch companion or watch app.

4. Inventory the build/verify/test conventions of this repo: exactly what
   scripts/test.sh runs, every Makefile target and command, how the simulator
   destination is resolved (SIM env var, .simulator_id, defaults), the signing
   and identity settings (DEVELOPMENT_TEAM, BUNDLE_ID, entitlements), what
   scripts/run-simulator.sh and scripts/run-devices.sh do, and whether any CI
   config exists.

5. Describe the git history of this repo (roughly the last 15 commits): what
   each commit changed, how the checklist UI evolved (initial button, edit
   overlay, reminder creation, green checkmark, Remove button), where the
   VAR-966 and VAR-967 work landed, and how the checklist concept is named and
   represented across the code.