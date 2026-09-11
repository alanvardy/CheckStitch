# Task

In the CheckStitch iOS app, when the user taps the checklist button (`createChecklistButton` in
`CheckStitch/ContentView.swift`), the async `createChecklistReminders()` work runs in a `Task {}`
with no visual feedback — the checklist name sits static while the reminders are created.

Show a **rotating icon to the right of the checklist name while the work is in progress**, and
replace it with a **green checkmark once the work finishes**. The checkmark disappears after about
1 second, returning the row to its resting state.

Scope is the tapping path for the existing checklist view only — no new screens, no changes to the
edit overlay (`EditChecklistView`), and no change to what `createChecklistReminders()` does.

## Why SMALL

Single module, one source file (`CheckStitch/ContentView.swift`), follows the file's existing
SwiftUI view patterns. 0–2 unknowns (rendering a spinner/success state; a 1s auto-clear, e.g. a
`Task.sleep`), no schema/API/data-model change, no new subsystem or shared code, and the spec is
concrete — rotating icon while working, green checkmark when done, gone after ~1s — so no design
decision or human sign-off is needed.

## Key files

- `CheckStitch/ContentView.swift` — the `ContentView` / `createChecklistButton` view; the working
  state lives next to the existing `Task { await createChecklistReminders() }` and
  `checklistName` `@State`. `MyApp.swift` and the edit-overlay sheet are untouched.