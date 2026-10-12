# Research Questions

## Context
Focus on the checklist destination data model and its Codable/merge format,
the sync and store layer that persists it, the run-time pipeline that turns a
checklist into reminders (including the destination-resolution seam and its
outcome states), the UI that configures the destination and runs a checklist,
the App Intents / Shortcuts that can run a checklist, and the widget/watch
surfaces that reuse any of these. Also relevant: localization conventions and
the test layout for these areas.

## Questions
1. How is a checklist's destination represented, persisted, decoded/encoded,
   and migrated in `Checklist` and its export format, and what happens when the
   field is absent or unknown in stored or imported data?
2. How does the destination-holding field flow through the sync and store layer
   (`ChecklistStore`, sync coordinator/merge), including last-write-wins
   conflict handling and cross-device reconciliation?
3. How does running a checklist turn items into reminders — what resolves the
   destination, what outcome/error states exist, and where is the access/permission
   gating applied?
4. How does the run-time UI let a user choose a destination and run a checklist,
   and where do the view model and the picker surface their states?
5. What are the App Intent entry points that can run a checklist and how does
   each perform, report failure, and expose parameters/configuration, including
   any App Shortcuts?
6. How do the widget and watch targets invoke or represent a checklist run, and
   what data do they pass across the app/watch boundary?
7. What localization and test conventions apply to user-facing destination and
   run strings, and how are the affected areas tested?