# Task

CheckStitch today holds exactly one implicit checklist (a name and item array in
`ContentView` `@State`, nothing persisted, resets on launch). Turn it into a
collection: a scrollable list of checklists on the main screen, a "Create
checklist" button that adds one and opens the edit overlay, tapping a checklist
opens the edit overlay (rename/add/remove/edit items, still creating reminders
with spinner and green checkmark per VAR-966), and a "Remove Checklist" button
that actually deletes the checklist being edited and dismisses.

Checklists must persist across launches, preferring the App Group container
(`group.app.alanvardy.CheckStitch`) so the planned watch app (VAR-963) reads the
same state. One open product question must be confirmed: deleting a checklist
should not delete the reminders it already created in Reminders. This supersedes
the no-op Remove button shipped in VAR-967 / PR #5.