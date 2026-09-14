# Research Questions

## Context

Focus on the CheckStitch Swift/SwiftUI codebase: the persisted Checklist model
and its versioned codec in CheckStitchCore and CheckStitch, the
Reminders/EventKit creation seam (ChecklistReminders.swift,
ReminderCreating.swift, EventKitReminderCreator), the creator/view model
outcome types, the edit-checklist screen (ChecklistDetailView.swift,
ContentView.swift), and the test suites (CheckStitchTests,
CheckStitchUITests). The reference implementation at
/Users/vardy/dev/SingleThread is also relevant for platform-integration
patterns.

## Questions

1. How does the Checklist model and its versioned codec define, decode, and
   default fields — in particular how ChecklistCodec, ChecklistEnvelope, and
   the store handle payloads that lack fields introduced in newer versions,
   and what classify/migration outcomes exist?

2. What Reminders list/calendar enumeration surface exists in the CheckStitch
   codebase and in the SingleThread reference implementation, and how are
   calendar/list identifiers represented, resolved, and used when creating
   reminders?

3. How does the existing reminder-creation flow deal with all-or-nothing
   concerns: where in the flow can partial or complete failure occur, what
   outcome/error types exist (ChecklistCreationOutcome, ReminderCreating,
   ReminderCreationOutcome), and how are outcomes currently surfaced in the
   UI?

4. How does the edit-checklist screen (ChecklistDetailView.swift) bind its
   draft state to the store and persist edits, and what control/binding
   patterns exist across the SwiftUI screens in the app target?

5. What test patterns and fixtures cover the model/codec, the EventKit seam,
   and the UI, and how are suite-level concerns like @MainActor and EventKit
   isolation handled in CheckStitchTests and CheckStitchUITests?