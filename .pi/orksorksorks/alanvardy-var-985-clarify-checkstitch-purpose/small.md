# Task

Update `AGENTS.md` (repo root of CheckStitch) to state what the app is for.
The app's purpose, to document verbatim:

- CheckStitch lets a user create "Checklists". Each checklist contains one or
  more "items". Checklists have a name, and each item has a name.
- Running a Checklist creates one reminder for each item in the Reminders
  inbox.
- The app does not delete or complete reminders. It does not edit reminders
  after they have been created. It is only for the purpose of bulk creating
  reminders.

The current `AGENTS.md` opens with a one-line app description; fold this
clarification in (for example as a purpose section near the top) so future
agents know exactly what CheckStitch is and — equally — what it deliberately
does not do. This is a documentation-only change; no code, no tests.

## Why SMALL

A–F all hold: one file (`AGENTS.md`), zero unknowns with the exact content
supplied in the ticket, no schema/migration, no new subsystem or shared code
touched, no design decision or sign-off needed, and no tests — the ticket
even names the file and the wording.

## Key files

- `AGENTS.md` (repo root) — the only file to change; currently opens with a
  one-line app description that should be expanded into the clarification
  above.