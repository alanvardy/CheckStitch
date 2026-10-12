# Research Questions

## Context
Focus on the checklist data model and its JSON codec, the checklist store and
its save/duplicate/import-export paths, the merge/sync (LWW) layer, the
in-app run flow (view model, reminders creator, scaling resolver), the App
Intents that run a checklist, and the UI surfaces (ChecklistDetailView,
watch detail view, widgets) that edit or display the scaling value. Also
cover the test-suite and localization conventions that surround these areas.

## Questions
1. How is the checklist scaling value stored on the model, validated and
   clamped, and encoded/decoded by the JSON codec, including how backward
   compatibility with already-persisted payloads is handled?
2. How does the run-a-checklist flow work end to end from inside the app —
   from the user action through the view model and into the reminders
   creator — and what role does the per-run `multipleOverride` parameter play
   in the scaling resolver?
3. How do the existing App Intents (particularly the one that runs a
   checklist) declare parameters, validate inputs, surface errors, and
   produce dialogs or interactive input, and what interactive-input patterns
   exist in the repo?
4. How do the UI surfaces edit and display the scaling value — the detail
   view's scaling field and badges, the watch detail view, and widget
   configuration views — including any platform-specific branches?
5. How do persistence and sync handle checklist fields — the store setters
   and save path, duplicate/fresh-copy, import/export, and the LWW merge
   field set — and which fields are currently carried through each path?
6. What test-suite patterns and localization conventions apply to changes in
   the model, codec, run path, intents, and detail view?